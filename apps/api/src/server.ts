import { buildApp } from './app.js'
import { env } from './config/env.js'

console.log('1 - server.ts carregado')

const app = buildApp()

console.log('2 - app criada')

try {
  console.log('3 - iniciando listen')

  await app.listen({
    port: env.port,
    host: '0.0.0.0',
  })

  console.log('4 - servidor iniciado')
} catch (error) {
  app.log.error(error)
  process.exit(1)
}