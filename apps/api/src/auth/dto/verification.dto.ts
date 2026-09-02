import { IsEnum, IsNotEmpty, IsString, Matches } from 'class-validator';
import { VerificationChannel } from '../auth.types';

export class VerifyAccountDto {
  @IsString()
  @IsNotEmpty()
  username!: string;

  @IsEnum(VerificationChannel)
  channel!: VerificationChannel;

  @IsString()
  @Matches(/^\d{6}$/)
  code!: string;
}

export class ResendVerificationDto {
  @IsString()
  @IsNotEmpty()
  username!: string;

  @IsEnum(VerificationChannel)
  channel!: VerificationChannel;
}
