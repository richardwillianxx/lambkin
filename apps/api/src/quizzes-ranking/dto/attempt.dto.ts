import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsInt,
  Min,
  ValidateNested,
} from 'class-validator';

export class QuizAnswerDto {
  @IsInt()
  @Min(1)
  questionId!: number;

  @IsInt()
  @Min(1)
  selectedOptionId!: number;
}

export class SubmitQuizAttemptDto {
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({
    each: true,
  })
  @Type(() => QuizAnswerDto)
  answers!: QuizAnswerDto[];
}