// Isolated model of Docker names, status, image and health; never calls Docker/AWS.
const fs = require('node:fs');
const [tool, ...a] = process.argv.slice(2);
const file = process.env.MOCK_STATE;
const s = JSON.parse(fs.readFileSync(file));
const fail = () => process.exit(1);
const save = () => fs.writeFileSync(file, JSON.stringify(s));
fs.appendFileSync(process.env.MOCK_LOG, `${tool} ${a.join(' ')}\n`);
if (tool === 'curl') {
 const c = s['cloudlaunch-app'];
 if (!c || c.status !== 'running' || (c.image === 'old' && process.env.UNHEALTHY_OLD === 'true') || (c.image === 'new' && process.env.UNHEALTHY_NEW === 'true')) fail();
 process.exit(0);
}
if (tool === 'sleep') process.exit(0);
if (tool !== 'docker') fail();
const [cmd, name] = a;
if (cmd === 'container') { if (!s[a[2]]) fail(); }
else if (cmd === 'inspect') {
 if (!s[name]) fail();
 const f = a.join(' ');
 console.log(f.includes('State.Status') ? s[name].status : f.includes('RestartPolicy') ? 'unless-stopped' : f.includes('PortBindings') ? '127.0.0.1:3000' : s[name].image);
} else if (cmd === 'image') process.exit(0);
else if (cmd === 'rename') {
 if (!s[name] || s[a[2]]) fail();
 s[a[2]] = s[name]; delete s[name]; save();
} else if (cmd === 'stop' || cmd === 'start') {
 if (!s[name]) fail();
 if (cmd === 'start' && s[name].image === 'old' && process.env.FAIL_START === 'true') fail();
 s[name].status = cmd === 'start' ? 'running' : 'exited'; save();
 if(cmd === 'stop' && process.env.SIGNAL_STOP === 'true') process.kill(process.ppid, 'SIGTERM');
} else if (cmd === 'update') { if (!s[a.at(-1)]) fail(); }
else if (cmd === 'run') {
 if (process.env.FAIL_RUN === 'true') fail();
 const n = a[a.indexOf('--name') + 1]; if (s[n]) fail();
 s[n] = {image:'new', status:'running'}; save();
} else if (cmd === 'rm') { delete s[a.at(-1)]; save(); }
else fail();
