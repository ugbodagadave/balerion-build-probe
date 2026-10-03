// laneD otel_probe2.js — probe /dev/otel-grpc.sock for BuildAgentApi/HostApi services
// (Lane C proved OTLP traces Export works; this tests whether any control-plane service
// is multiplexed on the same unix socket).
'use strict';
const http2 = require('http2');
const net = require('net');
const SOCK = '/dev/otel-grpc.sock';

function envelope(payload) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(payload.length, 0);
  return Buffer.concat([Buffer.from([0]), len, payload]);
}

function call(path, payload) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (o) => { if (!done) { done = true; resolve(o); } };
    let client;
    try { client = http2.connect('http://localhost', { createConnection: () => net.connect(SOCK) }); }
    catch (e) { return finish({ path, error: 'connect: ' + e.message }); }
    const result = { path, status: null, headers: null, trailers: null, dataHex: '', dataUtf8: '', error: null };
    const timer = setTimeout(() => { result.error = 'timeout'; try { client.close(); } catch (e) {} finish(result); }, 7000);
    client.on('error', (e) => { result.error = 'client: ' + e.message; clearTimeout(timer); finish(result); });
    let req;
    try {
      req = client.request({ ':method': 'POST', ':path': path, ':authority': 'localhost',
        'content-type': 'application/grpc', 'te': 'trailers', 'grpc-accept-encoding': 'identity' });
    } catch (e) { clearTimeout(timer); return finish({ path, error: 'request: ' + e.message }); }
    const chunks = [];
    req.on('response', (h) => { result.status = h[':status']; result.headers = h; });
    req.on('data', (d) => chunks.push(d));
    req.on('trailers', (t) => { result.trailers = t; });
    req.on('error', (e) => { result.error = 'req: ' + e.message; });
    req.on('end', () => {
      const b = Buffer.concat(chunks);
      result.dataHex = b.toString('hex').slice(0, 1000);
      result.dataUtf8 = b.toString('utf8').replace(/[^\x20-\x7e\n]/g, '.').slice(0, 500);
      clearTimeout(timer); try { client.close(); } catch (e) {} finish(result);
    });
    req.end(envelope(payload));
  });
}

(async () => {
  const tests = [
    '/not.a.Service/Unknown',
    '/build_ext.BuildAgentApi/BuildkitStatus',
    '/build_ext.BuildAgentApi/ReceiveSnapshot',
    '/vm_runner.HostApi/GetInitConfig',
    '/vm_init.GuestApi/Status',
    '/opentelemetry.proto.collector.trace.v1.TraceService/Export',
  ];
  for (const p of tests) console.log(JSON.stringify(await call(p, Buffer.alloc(0))));
})();
