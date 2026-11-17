const createApp = require('./app');
const config = require('./config');
const db = require('./db');

const app = createApp();

const server = app.listen(config.port, () => {
  console.log(`Музыкальный магазин слушает порт ${config.port} (окружение: ${config.env})`);
});

let stopping = false;
const shutdown = (signal) => () => {
  if (stopping) return;
  stopping = true;
  console.log(`Получен ${signal}, останавливаюсь...`);
  const deadline = setTimeout(() => process.exit(1), 15000);
  deadline.unref();
  server.close(async () => {
    try {
      await db.destroy();
      clearTimeout(deadline);
      process.exit(0);
    } catch (error) {
      console.error('Ошибка завершения:', error.message);
      process.exit(1);
    }
  });
};
process.on('SIGINT', shutdown('SIGINT'));
process.on('SIGTERM', shutdown('SIGTERM'));
