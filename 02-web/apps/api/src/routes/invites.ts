/**
 * 邀請 endpoints - 家人守護版的核心流程
 *
 * 設定者 (北漂子女) 端:
 *   POST /invites                    → 產生邀請碼, 回 { code, qrPayload, expiresAt }
 *
 * 被邀請者 (家鄉父母) 端:
 *   GET  /invites/:code              → 看邀請預覽 ({ watcherDisplayName, expiresAt })
 *   POST /invites/:code/accept       → 接受邀請, 建立 relationship
 *   POST /invites/:code/reject       → 拒絕
 *
 * 安全:
 * - 邀請碼 24h 過期, 單次使用
 * - accept 時會檢查:
 *   - 自己不能接受自己的邀請 (watcher != watched)
 *   - 兩人之間若已有 accepted/pending 關係, 拒絕重複建立
 */
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { and, eq, isNull } from 'drizzle-orm';
import { db } from '../db/client.js';
import { inviteCodes, relationships, users } from '../db/schema.js';
import { requireUser } from '../plugins/device.js';
import { generateInviteCode, INVITE_TTL_MS } from '../lib/invite-code.js';

const paramsSchema = z.object({
  code: z.string().min(6).max(16).regex(/^[A-Z0-9]+$/, '邀請碼格式不對'),
});

export const inviteRoutes: FastifyPluginAsync = async (app) => {
  // ============ POST /invites ============
  app.post('/invites', async (req, reply) => {
    const user = requireUser(req);

    // 最多重試 3 次碰撞 (8 字元 × 31 alphabet = 31^8 ≈ 8.5e11, 碰撞機率極低)
    let code: string | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      const candidate = generateInviteCode();
      try {
        await db.insert(inviteCodes).values({
          code: candidate,
          watcherUserId: user.id,
          expiresAt: new Date(Date.now() + INVITE_TTL_MS),
        });
        code = candidate;
        break;
      } catch (err) {
        // Postgres unique violation code = 23505
        const isDup = err instanceof Error && 'code' in err && (err as { code: string }).code === '23505';
        if (!isDup) throw err;
        // 碰撞, 繼續 retry
      }
    }

    if (!code) {
      reply.status(500);
      return { error: '產生邀請碼失敗, 請稍後再試' };
    }

    const expiresAt = new Date(Date.now() + INVITE_TTL_MS);
    return {
      code,
      qrPayload: `nearsafe://invite/${code}`, // deep link, mobile 端會處理
      expiresAt: expiresAt.toISOString(),
    };
  });

  // ============ GET /invites/:code ============
  app.get<{ Params: { code: string } }>('/invites/:code', async (req, reply) => {
    const parsed = paramsSchema.safeParse(req.params);
    if (!parsed.success) {
      reply.status(400);
      return { error: parsed.error.flatten() };
    }

    const invite = (
      await db
        .select({
          code: inviteCodes.code,
          watcherUserId: inviteCodes.watcherUserId,
          expiresAt: inviteCodes.expiresAt,
          consumedAt: inviteCodes.consumedAt,
          watcherDisplayName: users.displayName,
        })
        .from(inviteCodes)
        .leftJoin(users, eq(users.id, inviteCodes.watcherUserId))
        .where(eq(inviteCodes.code, parsed.data.code))
        .limit(1)
    ).at(0);

    if (!invite) {
      reply.status(404);
      return { error: '邀請碼不存在' };
    }
    if (invite.consumedAt) {
      reply.status(410);
      return { error: '邀請碼已被使用' };
    }
    if (invite.expiresAt < new Date()) {
      reply.status(410);
      return { error: '邀請碼已過期' };
    }

    return {
      code: invite.code,
      watcherDisplayName: invite.watcherDisplayName, // 可能 null, 由 mobile 端顯示「某位家人」
      expiresAt: invite.expiresAt.toISOString(),
    };
  });

  // ============ POST /invites/:code/accept ============
  app.post<{ Params: { code: string } }>('/invites/:code/accept', async (req, reply) => {
    const user = requireUser(req);
    const parsed = paramsSchema.safeParse(req.params);
    if (!parsed.success) {
      reply.status(400);
      return { error: parsed.error.flatten() };
    }

    // Transaction: 驗證邀請 + 建 relationship + 標記 consumed
    try {
      const result = await db.transaction(async (tx) => {
        const invite = (
          await tx.select().from(inviteCodes).where(eq(inviteCodes.code, parsed.data.code)).limit(1)
        ).at(0);
        if (!invite) return { error: '邀請碼不存在', status: 404 } as const;
        if (invite.consumedAt) return { error: '邀請碼已被使用', status: 410 } as const;
        if (invite.expiresAt < new Date()) return { error: '邀請碼已過期', status: 410 } as const;

        if (invite.watcherUserId === user.id) {
          return { error: '不能接受自己的邀請', status: 400 } as const;
        }

        // 檢查重複關係 (unique index 會擋, 但早點給友善錯誤)
        const existing = (
          await tx
            .select()
            .from(relationships)
            .where(
              and(
                eq(relationships.watcherUserId, invite.watcherUserId),
                eq(relationships.watchedUserId, user.id),
              ),
            )
            .limit(1)
        ).at(0);
        if (existing) return { error: '已有關係, 無需重複接受', status: 409, relationshipId: existing.id } as const;

        const [rel] = await tx
          .insert(relationships)
          .values({
            watcherUserId: invite.watcherUserId,
            watchedUserId: user.id,
            status: 'accepted',
            respondedAt: new Date(),
          })
          .returning();

        await tx
          .update(inviteCodes)
          .set({ consumedAt: new Date() })
          .where(eq(inviteCodes.code, invite.code));

        return { ok: true, relationshipId: rel!.id } as const;
      });

      if ('error' in result) {
        reply.status(result.status ?? 400);
        return { error: result.error };
      }
      return result;
    } catch (err) {
      req.log.error({ err }, '接受邀請失敗');
      reply.status(500);
      return { error: '伺服器錯誤' };
    }
  });

  // ============ POST /invites/:code/reject ============
  app.post<{ Params: { code: string } }>('/invites/:code/reject', async (req, reply) => {
    const parsed = paramsSchema.safeParse(req.params);
    if (!parsed.success) {
      reply.status(400);
      return { error: parsed.error.flatten() };
    }

    // 標記 consumed (等同於 reject, 不建 relationship)
    const result = await db
      .update(inviteCodes)
      .set({ consumedAt: new Date() })
      .where(and(eq(inviteCodes.code, parsed.data.code), isNull(inviteCodes.consumedAt)))
      .returning({ code: inviteCodes.code });

    if (result.length === 0) {
      reply.status(404);
      return { error: '邀請碼不存在或已被處理' };
    }

    return { ok: true };
  });
};
