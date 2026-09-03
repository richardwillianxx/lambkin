import {
  IsInt,
  IsNotEmpty,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class CreateMediaUploadUrlDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(255)
  originalFilename!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  mimeType!: string;

  @IsInt()
  @Min(1)
  @Max(104857600)
  sizeBytes!: number;
}

export class ConfirmMediaUploadDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  storageKey!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(255)
  originalFilename!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  mimeType!: string;

  @IsInt()
  @Min(1)
  @Max(104857600)
  sizeBytes!: number;
}

export class AttachMediaDto {
  @IsInt()
  @Min(1)
  mediaId!: number;

  @IsInt()
  @Min(1)
  position!: number;
}
