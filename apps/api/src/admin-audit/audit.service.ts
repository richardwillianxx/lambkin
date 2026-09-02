import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { AuditLogQueryDto } from './dto/audit-log-query.dto';

type AuditMetadataValue =
  | string
  | number
  | boolean
  | null
  | AuditMetadataValue[]
  | {
      [key: string]:
        AuditMetadataValue;
    };

type CreateAuditLogInput = {
  userId?: number | null;
  action: string;
  entityType?: string | null;
  entityId?: number | null;
  metadata?: {
    [key: string]:
      AuditMetadataValue;
  };
  ipAddress?: string | null;
};

@Injectable()
export class AuditService {
  constructor(
    private readonly prisma:
      PrismaService,
  ) {}

  async log(
    input: CreateAuditLogInput,
  ) {
    return this.prisma.audit_logs.create({
      data: {
        user_id:
          input.userId ?? null,
        action:
          input.action,
        entity_type:
          input.entityType ?? null,
        entity_id:
          input.entityId ?? null,
        metadata:
          input.metadata,
        ip_address:
          input.ipAddress ?? null,
      },
    });
  }

  async findAll(
    user: AccessTokenPayload,
    query: AuditLogQueryDto,
  ) {
    await this.ensureSystemAdmin(
      user.sub,
    );

    const page =
      query.page ?? 1;

    const limit =
      query.limit ?? 20;

    const from =
      query.from
        ? new Date(query.from)
        : undefined;

    const to =
      query.to
        ? new Date(query.to)
        : undefined;

    if (
      from &&
      to &&
      from > to
    ) {
      throw new BadRequestException(
        'A data inicial não pode ser maior que a data final.',
      );
    }

    const where = {
      ...(query.action
        ? {
            action:
              query.action,
          }
        : {}),
      ...(query.entityType
        ? {
            entity_type:
              query.entityType,
          }
        : {}),
      ...(query.entityId
        ? {
            entity_id:
              query.entityId,
          }
        : {}),
      ...(query.userId
        ? {
            user_id:
              query.userId,
          }
        : {}),
      ...(
        from || to
          ? {
              created_at: {
                ...(from
                  ? {
                      gte: from,
                    }
                  : {}),
                ...(to
                  ? {
                      lte: to,
                    }
                  : {}),
              },
            }
          : {}
      ),
    };

    const [
      total,
      items,
    ] =
      await this.prisma.$transaction([
        this.prisma.audit_logs.count({
          where,
        }),

        this.prisma.audit_logs.findMany({
          where,
          select: {
            id: true,
            user_id: true,
            action: true,
            entity_type: true,
            entity_id: true,
            metadata: true,
            ip_address: true,
            created_at: true,
            users: {
              select: {
                id: true,
                username: true,
                person: {
                  select: {
                    id: true,
                    full_name: true,
                    preferred_name: true,
                  },
                },
              },
            },
          },
          orderBy: [
            {
              created_at: 'desc',
            },
            {
              id: 'desc',
            },
          ],
          skip:
            (page - 1) *
            limit,
          take: limit,
        }),
      ]);

    return {
      page,
      limit,
      total,
      totalPages:
        Math.ceil(
          total / limit,
        ),
      items,
    };
  }

  async findOne(
    user: AccessTokenPayload,
    auditLogId: number,
  ) {
    await this.ensureSystemAdmin(
      user.sub,
    );

    const auditLog =
      await this.prisma.audit_logs.findUnique({
        where: {
          id: auditLogId,
        },
        select: {
          id: true,
          user_id: true,
          action: true,
          entity_type: true,
          entity_id: true,
          metadata: true,
          ip_address: true,
          created_at: true,
          users: {
            select: {
              id: true,
              username: true,
              person: {
                select: {
                  id: true,
                  full_name: true,
                  preferred_name: true,
                  role: true,
                },
              },
            },
          },
        },
      });

    if (!auditLog) {
      throw new NotFoundException(
        'Log de auditoria não encontrado.',
      );
    }

    return auditLog;
  }

  private async ensureSystemAdmin(
    userId: number,
  ) {
    const user =
      await this.prisma.users.findUnique({
        where: {
          id: userId,
        },
        select: {
          status: true,
          is_system_admin: true,
          person: {
            select: {
              status: true,
            },
          },
        },
      });

    if (
      !user ||
      user.status !== 'A' ||
      user.person.status !== 'A' ||
      !user.is_system_admin
    ) {
      throw new ForbiddenException(
        'Acesso permitido apenas para System Admin.',
      );
    }
  }
}