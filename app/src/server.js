
const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

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

if (require.main === module) {
  const server = app.listen(PORT, "0.0.0.0", () => {
    console.log(`CloudLaunch running on port ${PORT}`);
  });
  for (const signal of ["SIGTERM", "SIGINT"]) {
    process.once(signal, () => {
      console.log(`CloudLaunch shutting down: ${signal}`);
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(1), 8000).unref();
    });
  }
}

module.exports = app;
