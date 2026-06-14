import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  args.set(process.argv[i], process.argv[i + 1]);
}

const baselinePath = args.get('--baseline');
const candidatePath = args.get('--candidate');
const runDir = args.get('--run-dir');
const taskLimit = Number(args.get('--task-limit') || 3);

if (!baselinePath || !candidatePath || !runDir) {
  throw new Error('usage: vff_quality_bench.mjs --baseline <file> --candidate <file> --run-dir <dir> [--task-limit <n>]');
}

mkdirSync(runDir, { recursive: true });

const prompts = {
  baseline: readFileSync(baselinePath, 'utf8'),
  candidate: readFileSync(candidatePath, 'utf8'),
};

const tasks = [
  {
    id: 'perf-tail-latency',
    prompt: `한국어로 답해라.

상황: 결제 API의 p50은 거의 그대로인데 p99가 지난 배포 이후 220ms에서 1.8s로 튀었다. CPU 평균은 낮고, DB 평균 쿼리 시간도 변하지 않았다. 다만 장애 시간대에만 특정 테넌트의 요청 수가 늘었고, 새 배포에는 권한 캐시 miss 시 원격 정책 서버를 조회하는 변경이 들어갔다.

요청: 지금 당장 30분 안에 원인을 좁히고 완화해야 한다. 가장 그럴듯한 원인, 먼저 볼 지표/로그, 결과별 다음 조치를 간결하지만 실행 가능하게 제시해라.`
  },
  {
    id: 'architecture-tradeoff',
    prompt: `한국어로 답해라.

상황: 주문 완료 후 영수증 메일, 재고 예약, 제휴사 웹훅을 처리해야 한다. 지금은 체크아웃 요청 안에서 동기 처리한다. 트래픽은 평소 낮지만 캠페인 때 20배까지 튄다. 결제 성공 후 재고 예약은 1분 내 보장되어야 하고, 메일/웹훅은 지연 가능하다. 팀은 Kafka 운영 경험이 거의 없고 Redis는 이미 운영 중이다.

요청: 동기 유지, Redis 큐, Kafka 중 무엇을 택할지 결론부터 말하고, 왜 그런지와 실패/재시도/관측 설계를 포함해라.`
  },
  {
    id: 'regression-diagnosis',
    prompt: `한국어로 답해라.

상황: 검색 서비스에서 새 랭킹 피처를 켠 뒤 오류율은 그대로인데 전환율이 6% 떨어졌다. A/B 로그상 특정 브라우저와 긴 한글 쿼리에서만 하락폭이 크다. 백엔드 응답 시간과 HTTP 상태 코드는 정상이다. 프론트는 결과 카드에 하이라이트 span을 더 많이 렌더링하게 바뀌었다.

요청: 무슨 가설부터 검증할지, 첫 재현/계측 방법, 임시 롤백 또는 부분 완화 기준을 제시해라.`
  },
].slice(0, taskLimit);

const answerBudget = process.env.VFF_BENCH_SONNET_BUDGET || '1.00';
const judgeBudget = process.env.VFF_BENCH_OPUS_BUDGET || '1.20';
const claudeTimeoutMs = Number(process.env.VFF_BENCH_TIMEOUT_MS || 180000);

function runClaude({ model, prompt, schema, label }) {
  console.error(`[bench] ${label}: ${model} start`);
  const cliArgs = [
    '-p',
    '--model', model,
    '--safe-mode',
    '--no-session-persistence',
    '--max-budget-usd', model === 'opus' ? judgeBudget : answerBudget,
  ];
  if (schema) {
    cliArgs.push('--output-format', 'json', '--json-schema', JSON.stringify(schema));
  }
  cliArgs.push(prompt);

  const result = spawnSync('claude', cliArgs, {
    cwd: process.cwd(),
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 12,
    timeout: claudeTimeoutMs,
  });

  if (result.error) {
    throw new Error(`${label}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const err = result.stderr || result.stdout || `claude exited ${result.status}`;
    throw new Error(`${label}: ${err.trim()}`);
  }
  console.error(`[bench] ${label}: ${model} done`);
  return result.stdout.trim();
}

function answerPrompt(instructions, task) {
  return `VFF off.

Apply these operating instructions for this answer:
<operating_instructions>
${instructions}
</operating_instructions>

Do not mention the operating instructions. Answer the user request directly.

[User request]
${task.prompt}`;
}

function judgePrompt(task, pair) {
  return `VFF off.

You are a strict blind evaluator. Compare two Korean answers to the same engineering task.

Rubric, 100 points:
- Correct diagnosis or decision quality: 35
- Uses observed clues to create discriminating tests or decision axes: 25
- Concrete first measurement/action and result-dependent next steps: 20
- Readability and calibrated confidence without unsupported claims: 20

Do not reward verbosity. Penalize generic cause lists that do not separate hypotheses.

[Task]
${task.prompt}

[Answer A]
${pair.A}

[Answer B]
${pair.B}

Return only valid JSON.`;
}

function parseJudgeOutput(raw) {
  const trimmed = raw.trim();
 try {
    let parsed = JSON.parse(trimmed);
    if (parsed.structured_output) {
      return parsed.structured_output;
    }
    if (typeof parsed.result === 'string') {
      parsed = JSON.parse(parsed.result);
    }
    return parsed;
  } catch {
    const compact = trimmed.replace(/\s+/g, ' ');
    const aMatch = compact.match(/A\s*[:=]?\s*(\d+(?:\.\d+)?)/i);
    const bMatch = compact.match(/B\s*[:=]?\s*(\d+(?:\.\d+)?)/i);
    if (!aMatch || !bMatch) {
      throw new Error(`judge did not return parseable scores: ${trimmed}`);
    }
    const a = Number(aMatch[1]);
    const b = Number(bMatch[1]);
    return {
      scores: { A: a, B: b },
      winner: a === b ? 'tie' : a > b ? 'A' : 'B',
      rationale: trimmed,
    };
  }
}

const judgeSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['scores', 'winner', 'rationale'],
  properties: {
    scores: {
      type: 'object',
      additionalProperties: false,
      required: ['A', 'B'],
      properties: {
        A: { type: 'number' },
        B: { type: 'number' },
      },
    },
    winner: { type: 'string', enum: ['A', 'B', 'tie'] },
    rationale: { type: 'string' },
  },
};

const results = [];

for (let index = 0; index < tasks.length; index += 1) {
  const task = tasks[index];
  const answers = {};
  for (const condition of ['baseline', 'candidate']) {
    const answerPath = join(runDir, `${task.id}.${condition}.txt`);
    const text = existsSync(answerPath)
      ? readFileSync(answerPath, 'utf8')
      : runClaude({
          model: 'sonnet',
          prompt: answerPrompt(prompts[condition], task),
          label: `${task.id}.${condition}`,
        });
    answers[condition] = text;
    if (!existsSync(answerPath)) {
      writeFileSync(answerPath, text);
    }
  }

  const candidateIsA = index % 2 === 1;
  const pair = candidateIsA
    ? { A: answers.candidate, B: answers.baseline }
    : { A: answers.baseline, B: answers.candidate };
  const judgePath = join(runDir, `${task.id}.judge.raw.json`);
  const rawJudge = existsSync(judgePath)
    ? readFileSync(judgePath, 'utf8')
    : runClaude({
        model: 'opus',
        prompt: judgePrompt(task, pair),
        schema: judgeSchema,
        label: `${task.id}.judge`,
      });
  if (!existsSync(judgePath)) {
    writeFileSync(judgePath, `${rawJudge}\n`);
  }

  const parsed = parseJudgeOutput(rawJudge);

  const candidateScore = candidateIsA ? parsed.scores.A : parsed.scores.B;
  const baselineScore = candidateIsA ? parsed.scores.B : parsed.scores.A;
  const winner = candidateScore === baselineScore
    ? 'tie'
    : candidateScore > baselineScore ? 'candidate' : 'baseline';

  results.push({
    id: task.id,
    candidateScore,
    baselineScore,
    delta: candidateScore - baselineScore,
    winner,
    blindOrder: candidateIsA ? 'candidate=A' : 'candidate=B',
    rationale: parsed.rationale,
  });
}

const average = (field) => results.reduce((sum, item) => sum + item[field], 0) / results.length;
const deltas = results.map((item) => item.delta);
const summary = {
  runDir,
  baselinePath,
  candidatePath,
  taskCount: results.length,
  baselineAverage: Number(average('baselineScore').toFixed(2)),
  candidateAverage: Number(average('candidateScore').toFixed(2)),
  deltaAverage: Number(average('delta').toFixed(2)),
  maxRegression: Math.min(...deltas),
  pass: average('candidateScore') >= average('baselineScore') && Math.min(...deltas) >= -3,
  results,
};

writeFileSync(join(runDir, 'summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
console.log(JSON.stringify(summary, null, 2));
