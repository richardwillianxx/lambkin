import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsInt,
  IsNotEmpty,
  IsString,
  Min,
  ValidateNested,
} from 'class-validator';

export class QuizOptionDto {
  @IsString()
  @IsNotEmpty()
  optionText!: string;

  @IsBoolean()
  isCorrect!: boolean;

  @IsInt()
  @Min(1)
  position!: number;
}

export class QuizQuestionDto {
  @IsString()
  @IsNotEmpty()
  questionText!: string;

  @IsInt()
  @Min(0)
  points!: number;

  @IsInt()
  @Min(1)
  position!: number;

  @IsArray()
  @ArrayMinSize(2)
  @ValidateNested({
    each: true,
  })
  @Type(() => QuizOptionDto)
  options!: QuizOptionDto[];
}

export class UpdateQuizStructureDto {
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({
    each: true,
  })
  @Type(() => QuizQuestionDto)
  questions!: QuizQuestionDto[];
}
