import { BadRequestException, Injectable } from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import { QuizState, UpdateQuizStateDto } from './dto/quiz.dto';
import { UpdateQuizStructureDto } from './dto/quiz-structure.dto';
import { QuizzesService } from './quizzes.service';

@Injectable()
export class QuizStructureService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly quizzesService: QuizzesService,
  ) {}

  async updateStructure(
    user: AccessTokenPayload,
    quizId: number,
    dto: UpdateQuizStructureDto,
  ) {
    const quiz = await this.quizzesService.getQuizOrThrow(quizId);

    await this.quizzesService.ensureCanManageQuiz(
      user,
      quiz.created_by_user_id,
    );

    this.quizzesService.ensureQuizIsDraft(quiz.quiz_state);

    this.ensureValidStructure(dto);

    const attemptCount = await this.prisma.quiz_attempts.count({
      where: {
        quiz_id: quizId,
        status: 'A',
      },
    });

    if (attemptCount > 0) {
      throw new BadRequestException(
        'A estrutura do quiz não pode ser alterada após existirem tentativas.',
      );
    }

    await this.prisma.$transaction(async (tx) => {
      const currentQuestions = await tx.quiz_questions.findMany({
        where: {
          quiz_id: quizId,
          status: 'A',
        },
        select: {
          id: true,
        },
      });

      const questionIds = currentQuestions.map((question) => question.id);

      if (questionIds.length > 0) {
        await tx.quiz_options.updateMany({
          where: {
            question_id: {
              in: questionIds,
            },
            status: 'A',
          },
          data: {
            status: 'I',
          },
        });

        await tx.quiz_questions.updateMany({
          where: {
            id: {
              in: questionIds,
            },
            status: 'A',
          },
          data: {
            status: 'I',
          },
        });
      }

      for (const question of dto.questions) {
        const createdQuestion = await tx.quiz_questions.create({
          data: {
            quiz_id: quizId,
            question_text: question.questionText,
            points: question.points,
            position: question.position,
            status: 'A',
          },
        });

        await tx.quiz_options.createMany({
          data: question.options.map((option) => ({
            question_id: createdQuestion.id,
            option_text: option.optionText,
            is_correct: option.isCorrect,
            position: option.position,
            status: 'A',
          })),
        });
      }
    });

    return this.quizzesService.findOne(user, quizId);
  }

  async updateState(
    user: AccessTokenPayload,
    quizId: number,
    dto: UpdateQuizStateDto,
  ) {
    const quiz = await this.quizzesService.getQuizOrThrow(quizId);

    await this.quizzesService.ensureCanManageQuiz(
      user,
      quiz.created_by_user_id,
    );

    if (quiz.quiz_state === 'DRAFT' && dto.quizState === QuizState.ACTIVE) {
      await this.ensureStoredStructureIsValid(quizId);

      return this.prisma.quizzes.update({
        where: {
          id: quizId,
        },
        data: {
          quiz_state: 'ACTIVE',
        },
      });
    }

    if (quiz.quiz_state === 'ACTIVE' && dto.quizState === QuizState.CLOSED) {
      return this.prisma.quizzes.update({
        where: {
          id: quizId,
        },
        data: {
          quiz_state: 'CLOSED',
        },
      });
    }

    throw new BadRequestException('Transição de estado do quiz inválida.');
  }

  private ensureValidStructure(dto: UpdateQuizStructureDto) {
    this.ensureUniquePositions(
      dto.questions.map((question) => question.position),
      'As posições das perguntas não podem se repetir.',
    );

    for (const question of dto.questions) {
      this.ensureUniquePositions(
        question.options.map((option) => option.position),
        'As posições das alternativas de uma pergunta não podem se repetir.',
      );

      const correctOptions = question.options.filter(
        (option) => option.isCorrect,
      );

      if (correctOptions.length !== 1) {
        throw new BadRequestException(
          'Cada pergunta deve possuir exatamente uma alternativa correta.',
        );
      }
    }
  }

  private async ensureStoredStructureIsValid(quizId: number) {
    const questions = await this.prisma.quiz_questions.findMany({
      where: {
        quiz_id: quizId,
        status: 'A',
      },
      include: {
        quiz_options: {
          where: {
            status: 'A',
          },
        },
      },
      orderBy: {
        position: 'asc',
      },
    });

    if (questions.length === 0) {
      throw new BadRequestException(
        'O quiz precisa possuir pelo menos uma pergunta antes de ser ativado.',
      );
    }

    this.ensureUniquePositions(
      questions.map((question) => question.position),
      'As posições das perguntas não podem se repetir.',
    );

    for (const question of questions) {
      if (question.quiz_options.length < 2) {
        throw new BadRequestException(
          'Cada pergunta precisa possuir pelo menos duas alternativas.',
        );
      }

      this.ensureUniquePositions(
        question.quiz_options.map((option) => option.position),
        'As posições das alternativas de uma pergunta não podem se repetir.',
      );

      const correctOptions = question.quiz_options.filter(
        (option) => option.is_correct,
      );

      if (correctOptions.length !== 1) {
        throw new BadRequestException(
          'Cada pergunta deve possuir exatamente uma alternativa correta.',
        );
      }
    }
  }

  private ensureUniquePositions(positions: number[], message: string) {
    const uniquePositions = new Set(positions);

    if (uniquePositions.size !== positions.length) {
      throw new BadRequestException(message);
    }
  }
}
