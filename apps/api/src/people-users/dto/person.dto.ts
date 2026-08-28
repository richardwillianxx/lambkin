import {
  IsDateString,
  IsEmail,
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
} from 'class-validator';

export enum PersonRole {
  MINISTRY = 'MINISTRY',
  ASSISTANT = 'ASSISTANT',
  GUARDIAN = 'GUARDIAN',
  LAMB = 'LAMB',
}

export enum PersonGender {
  MALE = 'MALE',
  FEMALE = 'FEMALE',
}

export class CreatePersonDto {
  @IsInt()
  congregationId!: number;

  @IsEnum(PersonRole)
  role!: PersonRole;

  @IsEnum(PersonGender)
  gender!: PersonGender;

  @IsString()
  @IsNotEmpty()
  fullName!: string;

  @IsString()
  @IsNotEmpty()
  preferredName!: string;

  @IsDateString()
  birthDate!: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  whatsapp?: string;

  @IsOptional()
  @IsString()
  street?: string;

  @IsOptional()
  @IsString()
  number?: string;

  @IsOptional()
  @IsString()
  complement?: string;

  @IsOptional()
  @IsString()
  district?: string;

  @IsOptional()
  @IsString()
  city?: string;

  @IsOptional()
  @IsString()
  state?: string;

  @IsOptional()
  @IsString()
  zipCode?: string;

  @IsOptional()
  @IsString()
  notes?: string;
}

export class UpdatePersonDto {
  @IsOptional()
  @IsInt()
  congregationId?: number;

  @IsOptional()
  @IsEnum(PersonRole)
  role?: PersonRole;

  @IsOptional()
  @IsEnum(PersonGender)
  gender?: PersonGender;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  fullName?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  preferredName?: string;

  @IsOptional()
  @IsDateString()
  birthDate?: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  whatsapp?: string;

  @IsOptional()
  @IsString()
  street?: string;

  @IsOptional()
  @IsString()
  number?: string;

  @IsOptional()
  @IsString()
  complement?: string;

  @IsOptional()
  @IsString()
  district?: string;

  @IsOptional()
  @IsString()
  city?: string;

  @IsOptional()
  @IsString()
  state?: string;

  @IsOptional()
  @IsString()
  zipCode?: string;

  @IsOptional()
  @IsString()
  notes?: string;
}