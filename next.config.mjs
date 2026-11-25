/** @type {import('next').NextConfig} */
const nextConfig = {
  serverExternalPackages: ['pg'],
  // Los scripts SQL viajan con la función que reinicia la base de la demo
  outputFileTracingIncludes: { '/api/demo/reiniciar': ['./db/**/*.sql'] },
};
export default nextConfig;
