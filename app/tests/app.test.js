
const test = require("node:test");
const assert = require("node:assert/strict");
const request = require("supertest");

const app = require("../src/server");

test("GET / returns application details", async () => {
  const response = await request(app).get("/");

  assert.equal(response.status, 200);
  assert.equal(response.body.application, "CloudLaunch");
  assert.equal(response.body.version, "1.0.0");
});

test("GET /health returns healthy status", async () => {
  const response = await request(app).get("/health");

  assert.equal(response.status, 200);
  assert.equal(response.body.status, "healthy");
  assert.equal(response.body.service, "cloudlaunch-api");
});

