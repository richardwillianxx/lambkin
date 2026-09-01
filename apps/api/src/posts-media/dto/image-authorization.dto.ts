import {
  IsNotEmpty,
  IsString,
} from 'class-validator';

export class AuthorizeImageDto {
  @IsString()
  @IsNotEmpty()
  termsVersion!: string;
}