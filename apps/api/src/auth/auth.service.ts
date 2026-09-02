import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma/prisma.service';
import { AccessTokenPayload } from './auth.types';
import {
  generateRefreshToken,
  hashRefreshToken,
  REFRESH_TOKEN_TTL_MS,
} from './auth.utils';
import { LoginDto } from './dto/login.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  async login(dto: LoginDto) {
    const { username, password } = dto;

    const user = await this.prisma.users.findUnique({
      where: {
        username,
      },
      include: {
        person: true,
      },
    });

    if (!user || user.status !== 'A' || user.person.status !== 'A') {
      throw new UnauthorizedException('Usuário ou senha inválidos.');
    }

    const passwordIsValid = await argon2.verify(user.password_hash, password);

    if (!passwordIsValid) {
      throw new UnauthorizedException('Usuário ou senha inválidos.');
    }

    if (!user.email_verified_at && !user.whatsapp_verified_at) {
      throw new UnauthorizedException('Conta ainda não verificada.');
    }

    const refreshToken = generateRefreshToken();

    const session = await this.prisma.user_sessions.create({
      data: {
        user_id: user.id,
        refresh_token_hash: hashRefreshToken(refreshToken),
        expires_at: new Date(Date.now() + REFRESH_TOKEN_TTL_MS),
        status: 'A',
      },
    });

    const accessToken = await this.createAccessToken({
      sub: user.id,
      personId: user.person_id,
      sessionId: session.id,
      username: user.username,
      isSystemAdmin: user.is_system_admin,
    });

    return {
      accessToken,
      refreshToken,
      user: this.buildUserResponse(user),
    };
  }

  async refresh(refreshToken: string) {
    const refreshTokenHash = hashRefreshToken(refreshToken);

    const session = await this.prisma.user_sessions.findUnique({
      where: {
        refresh_token_hash: refreshTokenHash,
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
      session.status !== 'A' ||
      session.expires_at <= new Date()
    ) {
      throw new UnauthorizedException('Sessão inválida ou expirada.');
    }

    const user = session.users;

    if (
      user.status !== 'A' ||
      user.person.status !== 'A' ||
      (!user.email_verified_at && !user.whatsapp_verified_at)
    ) {
      throw new UnauthorizedException('Sessão inválida ou expirada.');
    }

    const newRefreshToken = generateRefreshToken();

    await this.prisma.user_sessions.update({
      where: {
        id: session.id,
      },
      data: {
        refresh_token_hash: hashRefreshToken(newRefreshToken),
        expires_at: new Date(Date.now() + REFRESH_TOKEN_TTL_MS),
      },
    });

    const accessToken = await this.createAccessToken({
      sub: user.id,
      personId: user.person_id,
      sessionId: session.id,
      username: user.username,
      isSystemAdmin: user.is_system_admin,
    });

    return {
      accessToken,
      refreshToken: newRefreshToken,
      user: this.buildUserResponse(user),
    };
  }

  async logout(sessionId: number) {
    await this.prisma.user_sessions.updateMany({
      where: {
        id: sessionId,
        status: 'A',
      },
      data: {
        status: 'I',
      },
    });
  }

  async me(userId: number) {
    const user = await this.prisma.users.findUnique({
      where: {
        id: userId,
      },
      include: {
        person: true,
      },
    });

    if (!user || user.status !== 'A' || user.person.status !== 'A') {
      throw new UnauthorizedException('Usuário não autenticado.');
    }

    return this.buildUserResponse(user);
  }

  private createAccessToken(payload: AccessTokenPayload) {
    return this.jwtService.signAsync(payload);
  }

  private buildUserResponse(user: {
    id: number;
    person_id: number;
    username: string;
    is_system_admin: boolean;
    person: {
      preferred_name: string;
      role: string;
    };
  }) {
    return {
      id: user.id,
      personId: user.person_id,
      username: user.username,
      isSystemAdmin: user.is_system_admin,
      preferredName: user.person.preferred_name,
      role: user.person.role,
    };
  }
}
