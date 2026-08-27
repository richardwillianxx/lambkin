import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  Res,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type {
  Request,
  Response,
} from 'express';
import { AuthCodeService } from './auth-code.service';
import { AuthService } from './auth.service';
import type { AccessTokenPayload } from './auth.types';
import {
  REFRESH_COOKIE_NAME,
  REFRESH_TOKEN_TTL_MS,
} from './auth.utils';
import { CurrentUser } from './current-user.decorator';
import { LoginDto } from './dto/login.dto';
import {
  ForgotPasswordDto,
  ResetPasswordDto,
} from './dto/password.dto';
import {
  ResendVerificationDto,
  VerifyAccountDto,
} from './dto/verification.dto';
import { JwtAuthGuard } from './jwt-auth.guard';

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly authCodeService: AuthCodeService,
    private readonly configService: ConfigService,
  ) {}

  @Post('login')
  async login(
    @Body() dto: LoginDto,
    @Res({ passthrough: true })
    response: Response,
  ) {
    const result =
      await this.authService.login(dto);

    this.setRefreshCookie(
      response,
      result.refreshToken,
    );

    return {
      accessToken: result.accessToken,
      user: result.user,
    };
  }

  @Post('refresh')
  async refresh(
    @Req() request: Request,
    @Res({ passthrough: true })
    response: Response,
  ) {
    const refreshToken =
      request.cookies?.[REFRESH_COOKIE_NAME];

    if (!refreshToken) {
      throw new UnauthorizedException(
        'Refresh token não informado.',
      );
    }

    const result =
      await this.authService.refresh(
        refreshToken,
      );

    this.setRefreshCookie(
      response,
      result.refreshToken,
    );

    return {
      accessToken: result.accessToken,
      user: result.user,
    };
  }

  @Post('logout')
  @UseGuards(JwtAuthGuard)
  async logout(
    @CurrentUser()
    user: AccessTokenPayload,
    @Res({ passthrough: true })
    response: Response,
  ) {
    await this.authService.logout(
      user.sessionId,
    );

    response.clearCookie(
      REFRESH_COOKIE_NAME,
      {
        path: '/auth',
      },
    );

    return {
      message: 'Sessão encerrada.',
    };
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  me(
    @CurrentUser()
    user: AccessTokenPayload,
  ) {
    return this.authService.me(user.sub);
  }

  @Post('verification/resend')
  resendVerification(
    @Body() dto: ResendVerificationDto,
  ) {
    return this.authCodeService
      .resendVerification(dto);
  }

  @Post('verification/confirm')
  verifyAccount(
    @Body() dto: VerifyAccountDto,
  ) {
    return this.authCodeService
      .verifyAccount(dto);
  }

  @Post('password/forgot')
  forgotPassword(
    @Body() dto: ForgotPasswordDto,
  ) {
    return this.authCodeService
      .forgotPassword(dto);
  }

  @Post('password/reset')
  resetPassword(
    @Body() dto: ResetPasswordDto,
  ) {
    return this.authCodeService
      .resetPassword(dto);
  }

  private setRefreshCookie(
    response: Response,
    token: string,
  ) {
    response.cookie(
      REFRESH_COOKIE_NAME,
      token,
      {
        httpOnly: true,
        secure:
          this.configService.get(
            'NODE_ENV',
          ) === 'production',
        sameSite: 'lax',
        maxAge: REFRESH_TOKEN_TTL_MS,
        path: '/auth',
      },
    );
  }
}