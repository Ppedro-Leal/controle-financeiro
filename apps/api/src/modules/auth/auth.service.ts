import {
  randomBytes,
  scrypt,
  timingSafeEqual,
} from 'node:crypto'

import { pool } from '../../database/pool.js'
import {
  createPasswordCredential,
  createUser,
  findUserCredentialByEmail,
} from './auth.repository.js'

import type {
  LoginBody,
  RegisterBody,
} from './auth.schema.js'

const SCRYPT_KEY_LENGTH = 64
const SCRYPT_COST = 32768
const SCRYPT_BLOCK_SIZE = 8
const SCRYPT_PARALLELIZATION = 3
const SCRYPT_MAX_MEMORY = 64 * 1024 * 1024

export class EmailAlreadyInUseError extends Error {}

export class InvalidCredentialsError extends Error {}

function deriveKey(
  password: string,
  salt: Buffer,
  keyLength = SCRYPT_KEY_LENGTH,
  cost = SCRYPT_COST,
  blockSize = SCRYPT_BLOCK_SIZE,
  parallelization = SCRYPT_PARALLELIZATION,
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(
      password,
      salt,
      keyLength,
      {
        cost,
        blockSize,
        parallelization,
        maxmem: SCRYPT_MAX_MEMORY,
      },
      (error, derivedKey) => {
        if (error) {
          reject(error)
          return
        }

        resolve(derivedKey)
      },
    )
  })
}

async function hashPassword(password: string) {
  const salt = randomBytes(16)

  const derivedKey = await deriveKey(
    password,
    salt,
  )

  return [
    'scrypt',
    SCRYPT_COST,
    SCRYPT_BLOCK_SIZE,
    SCRYPT_PARALLELIZATION,
    salt.toString('base64'),
    derivedKey.toString('base64'),
  ].join('$')
}

async function verifyPassword(
  password: string,
  storedHash: string,
) {
  const [
    algorithm,
    costValue,
    blockSizeValue,
    parallelizationValue,
    saltValue,
    hashValue,
  ] = storedHash.split('$')

  if (
    algorithm !== 'scrypt' ||
    !costValue ||
    !blockSizeValue ||
    !parallelizationValue ||
    !saltValue ||
    !hashValue
  ) {
    return false
  }

  const cost = Number(costValue)
  const blockSize = Number(blockSizeValue)
  const parallelization = Number(
    parallelizationValue,
  )

  if (
    !Number.isInteger(cost) ||
    !Number.isInteger(blockSize) ||
    !Number.isInteger(parallelization)
  ) {
    return false
  }

  const salt = Buffer.from(
    saltValue,
    'base64',
  )

  const expectedHash = Buffer.from(
    hashValue,
    'base64',
  )

  if (
    salt.length === 0 ||
    expectedHash.length === 0
  ) {
    return false
  }

  const derivedKey = await deriveKey(
    password,
    salt,
    expectedHash.length,
    cost,
    blockSize,
    parallelization,
  )

  return timingSafeEqual(
    derivedKey,
    expectedHash,
  )
}

function isUniqueViolation(error: unknown) {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === '23505'
  )
}

export async function registerUser(
  input: RegisterBody,
) {
  const passwordHash = await hashPassword(
    input.password,
  )

  const client = await pool.connect()

  try {
    await client.query('BEGIN')

    const user = await createUser(client, {
      name: input.name,
      email: input.email,
    })

    await createPasswordCredential(
      client,
      user.id,
      passwordHash,
    )

    await client.query('COMMIT')

    return user
  } catch (error) {
    await client.query('ROLLBACK')

    if (isUniqueViolation(error)) {
      throw new EmailAlreadyInUseError()
    }

    throw error
  } finally {
    client.release()
  }
}

export async function loginUser(
  input: LoginBody,
) {
  const credential =
    await findUserCredentialByEmail(
      input.email,
    )

  if (!credential) {
    throw new InvalidCredentialsError()
  }

  if (credential.status !== 'ACTIVE') {
    throw new InvalidCredentialsError()
  }

  const passwordMatches =
    await verifyPassword(
      input.password,
      credential.secret_hash,
    )

  if (!passwordMatches) {
    throw new InvalidCredentialsError()
  }

  return {
    id: credential.id,
    account_display_name:
      credential.account_display_name,
    email: credential.email,
  }
}