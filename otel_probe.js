// Lane C: probe host-side OTEL gRPC socket over HTTP/2 (node builtin, no deps)
const http2 = require('http2');
const net = require('net');

const SOCK = '/dev/otel-grpc.sock';
const OUT = [];

function frame(payload) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(payload.length, 0);
  return Buffer.concat([Buffer.from([0]), len, payload]);
}

function call(path, payload, label) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (obj) => { if (!done) { done = true; resolve(obj); } };
    let client;
    try {
      client = http2.connect('http://localhost', {
        createConnection: () => net.connect(SOCK),
      });
    } catch (e) { return finish({ label, error: String(e) }); }
    const result = { label, path, headers: null, trailers: null, data: '', error: null };
    const timer = setTimeout(() => {
      result.error = 'timeout';
      try { client.close(); } catch (e) {}
      finish(result);
    }, 6000);
    client.on('error', (e) => { result.error = 'client: ' + e.message; clearTimeout(timer); finish(result); });
    let req;
    try {
      req = client.request({
        ':method': 'POST',
        ':path': path,
        ':authority': 'localhost',
        'content-type': 'application/grpc',
        'te': 'trailers',
        'grpc-accept-encoding': 'identity,deflate,gzip',
      });
    } catch (e) { clearTimeout(timer); return finish({ label, error: String(e) }); }
    const chunks = [];
    req.on('response', (h) => { result.headers = h; });
    req.on('data', (d) => chunks.push(d));
    req.on('trailers', (t) => { result.trailers = t; });
    req.on('end', () => {
      result.data = Buffer.concat(chunks).toString('hex').slice(0, 2000);
      clearTimeout(timer);
      try { client.close(); } catch (e) {}
      finish(result);
    });
    req.on('error', (e) => { result.error = 'req: ' + e.message; clearTimeout(timer); finish(result); });
    req.end(frame(payload));
  });
}

(async () => {
  const tests = [
    ['/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo', Buffer.from([0x3a, 0x00]), 'refl-v1alpha-list'],
    ['/grpc.reflection.v1.ServerReflection/ServerReflectionInfo', Buffer.from([0x3a, 0x00]), 'refl-v1-list'],
    ['/grpc.health.v1.Health/Check', Buffer.alloc(0), 'health'],
    ['/opentelemetry.proto.collector.trace.v1.TraceService/Export', Buffer.alloc(0), 'otlp-traces-export'],
    ['/opentelemetry.proto.collector.metrics.v1.MetricsService/Export', Buffer.alloc(0), 'otlp-metrics-export'],
    ['/opentelemetry.proto.collector.logs.v1.LogsService/Export', Buffer.alloc(0), 'otlp-logs-export'],
  ];
  for (const [p, pl, label] of tests) {
    const r = await call(p, pl, label);
    OUT.push(JSON.stringify(r));
  }
  console.log(OUT.join('\n'));
})();
