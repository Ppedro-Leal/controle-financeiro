import type { PoolClient } from "pg";
import { pool } from "../../database/pool.js";

type CreateUserInput = {
  name: string;
  email: string;
};

export async function createUser(client: PoolClient, input: CreateUserInput) {
  const result = await client.query<{
    id: string;
    account_display_name: string;
    email: string;
  }>(
    `
      INSERT INTO users (
        account_display_name,
        email,
        account_type
      )
      VALUES ($1, $2, 'FULL')
      RETURNING
        id,
        account_display_name,
        email
    `,
    [input.name, input.email],
  );

  return result.rows[0];
}

export async function createPasswordCredential(
  client: PoolClient,
  userId: string,
  passwordHash: string,
) {
  await client.query(
    `
      INSERT INTO auth_credentials (
        user_id,
        type,
        secret_hash
      )
      VALUES ($1, 'EMAIL_PASSWORD', $2)
    `,
    [userId, passwordHash],
  );
}

export async function findUserCredentialByEmail(email: string) {
  const result = await pool.query<{
    id: string;
    account_display_name: string;
    email: string;
    status: string;
    secret_hash: string;
  }>(
    `
      SELECT
        u.id,
        u.account_display_name,
        u.email,
        u.status,
        ac.secret_hash
      FROM users u
      INNER JOIN auth_credentials ac
        ON ac.user_id = u.id
        AND ac.type = 'EMAIL_PASSWORD'
      WHERE LOWER(u.email) = LOWER($1)
      LIMIT 1
    `,
    [email],
  );

  return result.rows[0] ?? null;
}
