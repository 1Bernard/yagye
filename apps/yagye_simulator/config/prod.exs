import Config

config :simulator, Simulator.Web.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true,
  force_ssl: [hsts: true]
