import { IsEnum } from 'class-validator';

export enum ReactionType {
  HEART = 'HEART',
  CLAP = 'CLAP',
}

export class ReactToPostDto {
  @IsEnum(ReactionType)
  reactionType!: ReactionType;
}
