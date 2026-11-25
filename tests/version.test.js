const request = require('supertest');
const createApp = require('../src/app');

test('отдаёт SHA запущенного образа без авторизации', async () => {
  const previous = process.env.APP_REVISION;
  process.env.APP_REVISION = 'a'.repeat(40);
  try {
    const response = await request(createApp()).get('/version');
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ revision: 'a'.repeat(40) });
    expect(response.headers['cache-control']).toBe('no-store');
  } finally {
    if (previous === undefined) delete process.env.APP_REVISION;
    else process.env.APP_REVISION = previous;
  }
});
