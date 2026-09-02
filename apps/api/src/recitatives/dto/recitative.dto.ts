import {
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  Min,
} from 'class-validator';

export enum RecitativeGroupNumber {
  FIRST = 'FIRST',
  SECOND = 'SECOND',
  THIRD = 'THIRD',
  FOURTH = 'FOURTH',
}

export enum RecitativeGender {
  MALE = 'MALE',
  FEMALE = 'FEMALE',
}

export class CreateRecitativeDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsEnum(RecitativeGroupNumber)
  groupNumber!: RecitativeGroupNumber;

  @IsString()
  @IsNotEmpty()
  bibleBook!: string;

  @IsInt()
  @Min(1)
  bibleChapter!: number;

  @IsString()
  @IsNotEmpty()
  bibleVerse!: string;

  @IsEnum(RecitativeGender)
  gender!: RecitativeGender;

  @IsOptional()
  @IsInt()
  @Min(1)
  congregationId?: number;

  @Matches(
    /^\d{4}-\d{2}-\d{2}$/,
    {
      message:
        'recitativeDate deve estar no formato YYYY-MM-DD.',
    },
  )
  recitativeDate!: string;

  @IsOptional()
  @IsString()
  afterText?: string | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  recitersCount?: number | null;
}

export class UpdateRecitativeDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  name?: string;

  @IsOptional()
  @IsEnum(RecitativeGroupNumber)
  groupNumber?: RecitativeGroupNumber;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  bibleBook?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  bibleChapter?: number;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  bibleVerse?: string;

  @IsOptional()
  @IsEnum(RecitativeGender)
  gender?: RecitativeGender;

  @IsOptional()
  @Matches(
    /^\d{4}-\d{2}-\d{2}$/,
    {
      message:
        'recitativeDate deve estar no formato YYYY-MM-DD.',
    },
  )
  recitativeDate?: string;

  @IsOptional()
  @IsString()
  afterText?: string | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  recitersCount?: number | null;
}