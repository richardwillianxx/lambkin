import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma/prisma.service';
import { AccessTokenPayload } from './auth.types';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(
    context: ExecutionContext,
  ): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest();

    const authorization =
      request.headers.authorization;

    if (
      !authorization ||
      !authorization.startsWith('Bearer ')
    ) {
      throw new UnauthorizedException(
        'Token de acesso não informado.',
      );
    }

    const token = authorization.substring(7);

    let payload: AccessTokenPayload;

    try {
      payload =
        await this.jwtService.verifyAsync<AccessTokenPayload>(
          token,
        );
    } catch {
      throw new UnauthorizedException(
        'Token de acesso inválido ou expirado.',
      );
    }

    const session =
      await this.prisma.user_sessions.findUnique({
        where: {
          id: payload.sessionId,
        },
        include: {
          users: {
            include: {
              person: true,
            },
          },
        },
      });

    if (
      !session ||
      session.user_id !== payload.sub ||
      session.status !== 'A' ||
      session.expires_at <= new Date() ||
      session.users.status !== 'A' ||
      session.users.person.status !== 'A'
    ) {
      throw new UnauthorizedException(
        'Sessão inválida ou expirada.',
      );
    }

    request.user = payload;

    return true;
  }
}