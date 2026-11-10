
const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

const services = [
  { id: 1, name: "Web application", environment: "production", status: "healthy", uptime: "99.99%" },
  { id: 2, name: "API service", environment: "production", status: "healthy", uptime: "99.95%" },
  { id: 3, name: "Worker queue", environment: "staging", status: "degraded", uptime: "98.72%" }
];

app.get("/", (req, res) => {
  res.json({
    application: "CloudLaunch",
    message: "Welcome to my DevOps CI/CD Project!",
    version: process.env.APP_VERSION || "1.0.0",
    environment: process.env.NODE_ENV || "development"
  });
});

app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    service: "cloudlaunch-api"
  });
});

app.get("/api/services", (req, res) => {
  res.json({ services });
});

app.post("/api/services", (req, res) => {
  const { name, environment = "staging" } = req.body || {};

  if (!name || typeof name !== "string" || !name.trim()) {
    return res.status(400).json({ error: "A service name is required" });
  }

  const service = {
    id: Date.now(),
    name: name.trim(),
    environment,
    status: "healthy",
    uptime: "100.00%"
  };

  services.push(service);
  return res.status(201).json({ service });
});

if (require.main === module) {
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`CloudLaunch running on port ${PORT}`);
  });
}

module.exports = app;
