import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

const statusTone = { healthy: "green", degraded: "yellow" };

function App() {
  const [services, setServices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [serviceName, setServiceName] = useState("");

  async function loadServices() {
    setLoading(true);
    try {
      const response = await fetch("/api/services");
      if (!response.ok) throw new Error("Unable to reach the API");
      const data = await response.json();
      setServices(data.services);
      setError("");
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { loadServices(); }, []);

  async function addService(event) {
    event.preventDefault();
    if (!serviceName.trim()) return;
    const response = await fetch("/api/services", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: serviceName })
    });
    if (response.ok) {
      setServiceName("");
      loadServices();
    }
  }

  const healthyCount = services.filter(({ status }) => status === "healthy").length;

  return (
    <main className="shell">
      <nav className="nav"><div className="brand"><span className="brand-mark">✦</span> CloudLaunch</div><span className="nav-status"><i /> All systems monitored</span></nav>
      <section className="hero"><div><p className="eyebrow">OPERATIONS / OVERVIEW</p><h1>Ship with confidence.</h1><p className="intro">A calm, clear view of every service running in your delivery pipeline.</p></div><button className="refresh" onClick={loadServices}>↻ Refresh data</button></section>
      {error && <div className="error">{error}</div>}
      <section className="metrics"><div className="metric"><span>Services online</span><strong>{healthyCount}<small> / {services.length}</small></strong><em className="positive">↑ 100% this week</em></div><div className="metric"><span>Deployments today</span><strong>24</strong><em className="positive">↑ 18% vs yesterday</em></div><div className="metric"><span>Avg. response time</span><strong>142<small> ms</small></strong><em className="neutral">— within target</em></div></section>
      <section className="content-grid"><div className="panel services-panel"><div className="panel-heading"><div><p className="eyebrow">LIVE INVENTORY</p><h2>Service health</h2></div><span className="live-dot">● LIVE</span></div>{loading ? <p className="muted">Loading services…</p> : <div className="service-list">{services.map((service) => <article className="service" key={service.id}><div className={`service-icon ${statusTone[service.status]}`}>⌁</div><div className="service-info"><h3>{service.name}</h3><p>{service.environment} · uptime {service.uptime}</p></div><span className={`badge ${statusTone[service.status]}`}>{service.status}</span><span className="arrow">→</span></article>)}</div>}</div><aside className="panel deploy-panel"><p className="eyebrow">QUICK ACTION</p><h2>Add a service</h2><p className="muted">Connect a new service to your control room.</p><form onSubmit={addService}><label htmlFor="service-name">Service name</label><input id="service-name" value={serviceName} onChange={(event) => setServiceName(event.target.value)} placeholder="e.g. Billing API" /><button type="submit">Add to inventory <span>→</span></button></form><div className="tip"><span>✦</span><p><strong>Tip</strong><br />Keep service names short and recognizable for your team.</p></div></aside></section>
      <footer>CloudLaunch <span>•</span> Built for reliable delivery</footer>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
