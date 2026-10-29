import { createApp } from './app.js';

const port = Number(process.env.PORT ?? 3000);
const { server, config } = createApp();
server.listen(port, '0.0.0.0', () => {
  console.log(`REBS HRMS mock API on http://0.0.0.0:${port} (tz ${config.timezone}, dev controls ${config.devControls ? 'ON' : 'OFF'})`);
});
