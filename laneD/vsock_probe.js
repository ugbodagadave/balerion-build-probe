// laneD vsock_probe.js — h2/gRPC probe over an inherited connected AF_VSOCK fd.
// Launched by vsock32 `call` mode: env VSOCK_FD, VSOCK_CID, VSOCK_PORT.
// Node builtins only (net + http2). Output: JSON lines to stdout.
'use strict';
const net = require('net');
const http2 = require('http2');

const fd = parseInt(process.env.VSOCK_FD || '-1', 10);
const cid = process.env.VSOCK_CID || '?';
const port = process.env.VSOCK_PORT || '?';

function envelope(payload) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(payload.length, 0);
  return Buffer.concat([Buffer.from([0]), len, payload]);
}

const sock = new net.Socket({ fd, readable: true, writable: true });
try {
  const a = sock.address();
  console.log(JSON.stringify({ event: 'addr', local: a, remote: { address: sock.remoteAddress, port: sock.remotePort } }));
} catch (e) {
  console.log(JSON.stringify({ event: 'addr_err', error: String(e.message || e) }));
}

const METHODS = [
  // control: must be UNIMPLEMENTED (12)
  '/not.a.Service/Unknown',
  // read-only / status
  '/build_ext.BuildAgentApi/BuildkitStatus',
  '/vm_runner.HostApi/GetInitConfig',
  '/vm_runner.HostApi/GetHostTime',
  '/vm_runner.HostApi/GetTraceContext',
  '/vm_init.GuestApi/Status',
  '/vm_init.GuestApi/Ping',
  // empty-message probes on stateful methods (observe validation / side effects)
  '/build_ext.BuildAgentApi/ReceiveSnapshot',
  '/build_ext.BuildAgentApi/PrepareSession',
  '/build_ext.BuildAgentApi/CleanupSession',
  '/build_ext.BuildAgentApi/DownloadSnapshot',
  '/build_ext.BuildAgentApi/UnpackSnapshot',
  '/build_ext.BuildAgentApi/DiffSnapshots',
  '/build_ext.BuildAgentApi/BuildkitSolve',
  '/build_ext.BuildAgentApi/ImagePublish',
  '/build_ext.BuildAgentApi/UploadSnapshot',
];

function call(client, path, payload) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (o) => { if (!done) { done = true; resolve(o); } };
    const result = { cid, port, path, status: null, headers: null, trailers: null,
                     dataHex: '', dataUtf8: '', error: null, rstCode: null };
    const timer = setTimeout(() => { result.error = 'timeout'; try { req.close(); } catch (e) {} finish(result); }, 8000);
    let req;
    try {
      req = client.request({
        ':method': 'POST', ':path': path, ':scheme': 'http',
        ':authority': 'vsock', 'content-type': 'application/grpc',
        'te': 'trailers', 'grpc-accept-encoding': 'identity',
      });
    } catch (e) { clearTimeout(timer); result.error = 'request: ' + e.message; return finish(result); }
    const chunks = [];
    req.on('response', (h) => { result.status = h[':status']; result.headers = h; });
    req.on('data', (d) => chunks.push(d));
    req.on('trailers', (t) => { result.trailers = t; });
    req.on('close', () => { result.rstCode = req.rstCode; });
    req.on('error', (e) => { result.error = 'req: ' + e.message; });
    req.on('end', () => {
      const b = Buffer.concat(chunks);
      result.dataHex = b.toString('hex').slice(0, 4000);
      result.dataUtf8 = b.toString('utf8').replace(/[^\x20-\x7e\n]/g, '.').slice(0, 2000);
      clearTimeout(timer);
      finish(result);
    });
    req.end(envelope(payload));
  });
}

const client = http2.connect('http://vsock', { createConnection: () => sock });
client.on('error', (e) => console.log(JSON.stringify({ event: 'session_err', error: String(e.message || e) })));

(async () => {
  await new Promise((res) => {
    const t = setTimeout(res, 5000);
    client.on('connect', () => { clearTimeout(t); res(); });
    client.on('error', () => { clearTimeout(t); res(); });
  });
  console.log(JSON.stringify({ event: 'session_connected', cid, port }));
  for (const p of METHODS) {
    const r = await call(client, p, Buffer.alloc(0));
    console.log(JSON.stringify(r));
  }
  try { client.close(); } catch (e) {}
  process.exit(0);
})();
