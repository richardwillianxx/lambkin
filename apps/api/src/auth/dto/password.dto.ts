import {
  IsEnum,
  IsNotEmpty,
  IsString,
  Matches,
  MinLength,
} from 'class-validator';
import { VerificationChannel } from '../auth.types';

export class ForgotPasswordDto {
  @IsString()
  @IsNotEmpty()
  username!: string;

  @IsEnum(VerificationChannel)
  channel!: VerificationChannel;
}

export class ResetPasswordDto {
  @IsString()
  @IsNotEmpty()
  username!: string;

  @IsString()
  @Matches(/^\d{6}$/)
  code!: string;

  @IsString()
  @MinLength(6)
  newPassword!: string;
}