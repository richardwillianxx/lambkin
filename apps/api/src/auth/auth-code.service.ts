import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as argon2 from 'argon2';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { VerificationChannel } from './auth.types';
import { generateAuthCode, hashAuthCode } from './auth.utils';
import {
  ResendVerificationDto,
  VerifyAccountDto,
} from './dto/verification.dto';
import { ForgotPasswordDto, ResetPasswordDto } from './dto/password.dto';

@Injectable()
export class AuthCodeService {
  private readonly codeSecret: string;

  constructor(
    private readonly prisma: PrismaService,
    configService: ConfigService,
  ) {
    this.codeSecret = configService.getOrThrow<string>('AUTH_CODE_SECRET');
  }

  async resendVerification(dto: ResendVerificationDto) {
    const user = await this.findUser(dto.username);

    if (!user) {
      return this.genericVerificationResponse();
    }

    if (user.email_verified_at || user.whatsapp_verified_at) {
      return {
        message: 'Conta já verificada.',
      };
    }

    if (!this.hasChannel(user, dto.channel)) {
      throw new BadRequestException('Canal de verificação indisponível.');
    }

    const type =
      dto.channel === VerificationChannel.EMAIL
        ? 'EMAIL_VERIFICATION'
        : 'WHATSAPP_VERIFICATION';

    const code = await this.createCode(user.id, type);

    return this.codeResponse('Código de verificação gerado.', code);
  }

  async verifyAccount(dto: VerifyAccountDto) {
    const user = await this.findUser(dto.username);

    if (!user) {
      throw new BadRequestException('Código inválido ou expirado.');
    }

    const type =
      dto.channel === VerificationChannel.EMAIL
        ? 'EMAIL_VERIFICATION'
        : 'WHATSAPP_VERIFICATION';

    const token = await this.validateCode(user.id, type, dto.code);

    await this.prisma.$transaction([
      this.prisma.user_tokens.update({
        where: {
          id: token.id,
        },
        data: {
          status: 'I',
          used_at: new Date(),
        },
      }),

      this.prisma.users.update({
        where: {
          id: user.id,
        },
        data:
          dto.channel === VerificationChannel.EMAIL
            ? {
                email_verified_at: new Date(),
              }
            : {
                whatsapp_verified_at: new Date(),
              },
      }),
    ]);

    return {
      message: 'Conta verificada com sucesso.',
    };
  }

  async forgotPassword(dto: ForgotPasswordDto) {
    const user = await this.findUser(dto.username);

    if (
      !user ||
      user.status !== 'A' ||
      user.person.status !== 'A' ||
      !this.hasChannel(user, dto.channel)
    ) {
      return this.genericPasswordResponse();
    }

    const code = await this.createCode(user.id, 'PASSWORD_RESET');

    return this.codeResponse('Código de recuperação gerado.', code);
  }

  async resetPassword(dto: ResetPasswordDto) {
    const user = await this.findUser(dto.username);

    if (!user) {
      throw new BadRequestException('Código inválido ou expirado.');
    }

    const token = await this.validateCode(user.id, 'PASSWORD_RESET', dto.code);

    const passwordHash = await argon2.hash(dto.newPassword, {
      type: argon2.argon2id,
    });

    await this.prisma.$transaction([
      this.prisma.users.update({
        where: {
          id: user.id,
        },
        data: {
          password_hash: passwordHash,
        },
      }),

      this.prisma.user_tokens.update({
        where: {
          id: token.id,
        },
        data: {
          status: 'I',
          used_at: new Date(),
        },
      }),

      this.prisma.user_sessions.updateMany({
        where: {
          user_id: user.id,
          status: 'A',
        },
        data: {
          status: 'I',
        },
      }),
    ]);

    return {
      message: 'Senha alterada com sucesso.',
    };
  }

  private async findUser(username: string) {
    return this.prisma.users.findUnique({
      where: {
        username,
      },
      include: {
        person: true,
        verificationPerson: true,
      },
    });
  }

  private hasChannel(
    user: Awaited<ReturnType<AuthCodeService['findUser']>>,
    channel: VerificationChannel,
  ): boolean {
    if (!user) {
      return false;
    }

    const contactPerson = user.verificationPerson ?? user.person;

    if (channel === VerificationChannel.EMAIL) {
      return Boolean(contactPerson.email);
    }

    return Boolean(contactPerson.whatsapp);
  }

  private async createCode(
    userId: number,
    tokenType:
      'EMAIL_VERIFICATION' | 'WHATSAPP_VERIFICATION' | 'PASSWORD_RESET',
  ) {
    await this.prisma.user_tokens.updateMany({
      where: {
        user_id: userId,
        token_type: tokenType,
        status: 'A',
      },
      data: {
        status: 'I',
      },
    });

    const code = generateAuthCode();

    const token = await this.prisma.user_tokens.create({
      data: {
        user_id: userId,
        token_type: tokenType,
        token_hash: randomBytes(32).toString('hex'),
        expires_at: new Date(Date.now() + 10 * 60 * 1000),
        attempts: 0,
        status: 'A',
      },
    });

    await this.prisma.user_tokens.update({
      where: {
        id: token.id,
      },
      data: {
        token_hash: hashAuthCode(token.id, code, this.codeSecret),
      },
    });

    return code;
  }

  private async validateCode(
    userId: number,
    tokenType:
      'EMAIL_VERIFICATION' | 'WHATSAPP_VERIFICATION' | 'PASSWORD_RESET',
    code: string,
  ) {
    const token = await this.prisma.user_tokens.findFirst({
      where: {
        user_id: userId,
        token_type: tokenType,
        status: 'A',
        used_at: null,
      },
      orderBy: {
        created_at: 'desc',
      },
    });

    if (!token) {
      throw new BadRequestException('Código inválido ou expirado.');
    }

    if (token.expires_at <= new Date() || token.attempts >= 5) {
      await this.prisma.user_tokens.update({
        where: {
          id: token.id,
        },
        data: {
          status: 'I',
        },
      });

      throw new BadRequestException('Código inválido ou expirado.');
    }

    const expectedHash = hashAuthCode(token.id, code, this.codeSecret);

    if (expectedHash !== token.token_hash) {
      const attempts = token.attempts + 1;

      await this.prisma.user_tokens.update({
        where: {
          id: token.id,
        },
        data: {
          attempts,
          status: attempts >= 5 ? 'I' : 'A',
        },
      });

      throw new BadRequestException('Código inválido ou expirado.');
    }

    return token;
  }

  private genericVerificationResponse() {
    return {
      message: 'Se a conta existir, um código de verificação será enviado.',
    };
  }

  private genericPasswordResponse() {
    return {
      message: 'Se a conta existir, um código de recuperação será enviado.',
    };
  }

  private codeResponse(message: string, code: string) {
    if (process.env.NODE_ENV === 'production') {
      return { message };
    }

    return {
      message,
      developmentCode: code,
    };
  }
}
