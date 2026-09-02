import { IsIn, IsInt } from 'class-validator';

export const GUARDIAN_RELATIONSHIPS = [
  'FATHER',
  'MOTHER',
  'GRANDFATHER',
  'GRANDMOTHER',
  'LEGAL_GUARDIAN',
  'OTHER',
] as const;

export type GuardianRelationship = (typeof GUARDIAN_RELATIONSHIPS)[number];

export class LinkGuardianDto {
  @IsInt()
  guardianPersonId!: number;

  @IsIn(GUARDIAN_RELATIONSHIPS)
  relationship!: GuardianRelationship;
}
