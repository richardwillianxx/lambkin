import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { QuizAttemptsService } from './quiz-attempts.service';
import { QuizStructureService } from './quiz-structure.service';
import { QuizzesController } from './quizzes.controller';
import { QuizzesService } from './quizzes.service';

@Module({
  imports: [
    AuthModule,
  ],
  controllers: [
    QuizzesController,
  ],
  providers: [
    QuizzesService,
    QuizStructureService,
    QuizAttemptsService,
  ],
})
export class QuizzesRankingModule {}