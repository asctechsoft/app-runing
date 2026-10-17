// Trang tối thiểu: backend chỉ phục vụ API.
export default function Home() {
  return (
    <main style={{ fontFamily: "system-ui, sans-serif", padding: 24 }}>
      <h1>STRIDE API</h1>
      <p>API only. See /api/health and openapi.yaml (versioned under /api/v1).</p>
    </main>
  );
}
