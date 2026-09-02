import {
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';

export enum QuizState {
  DRAFT = 'DRAFT',
  ACTIVE = 'ACTIVE',
  CLOSED = 'CLOSED',
}

export class CreateQuizDto {
  @IsString()
  @IsNotEmpty()
  title!: string;

  @IsOptional()
  @IsString()
  description?: string | null;

  @IsInt()
  @Min(1)
  maxAttempts!: number;
}

export class UpdateQuizDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  title?: string;

  @IsOptional()
  @IsString()
  description?: string | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  maxAttempts?: number;
}

export class UpdateQuizStateDto {
  @IsEnum(QuizState)
  quizState!: QuizState;
}
