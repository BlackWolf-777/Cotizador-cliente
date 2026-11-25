/** @type {import('next').NextConfig} */
const seguridad = [
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
  { key: 'Content-Security-Policy', value: "frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'" },
];
const nextConfig = {
  poweredByHeader: false,
  serverExternalPackages: ['pg'],
  // Los scripts SQL viajan con la función que reinicia la base de la demo
  outputFileTracingIncludes: { '/api/demo/reiniciar': ['./db/**/*.sql'] },
  async headers() { return [{ source: '/:path*', headers: seguridad }]; },
};
export default nextConfig;
