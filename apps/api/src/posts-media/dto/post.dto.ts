import {
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
} from 'class-validator';

export class CreatePostDto {
  @IsString()
  @IsNotEmpty()
  caption!: string;

  @IsOptional()
  @IsInt()
  congregationId?: number;
}

export class UpdatePostDto {
  @IsString()
  @IsNotEmpty()
  caption!: string;
}