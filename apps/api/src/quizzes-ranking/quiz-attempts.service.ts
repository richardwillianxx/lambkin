import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import {
  SubmitQuizAttemptDto,
} from './dto/attempt.dto';
import { QuizzesService } from './quizzes.service';

@Injectable()
export class QuizAttemptsService {
  constructor(
    private readonly prisma:
      PrismaService,
    private readonly quizzesService:
      QuizzesService,
  ) {}

  async submitAttempt(
    user: AccessTokenPayload,
    quizId: number,
    dto: SubmitQuizAttemptDto,
  ) {
    const quiz =
      await this.prisma.quizzes.findFirst({
        where: {
          id: quizId,
          status: 'A',
        },
        include: {
          quiz_questions: {
            where: {
              status: 'A',
            },
            orderBy: {
              position: 'asc',
            },
            include: {
              quiz_options: {
                where: {
                  status: 'A',
                },
                orderBy: {
                  position: 'asc',
                },
              },
            },
          },
        },
      });

    if (!quiz) {
      throw new NotFoundException(
        'Quiz não encontrado.',
      );
    }

    if (
      quiz.quiz_state !== 'ACTIVE'
    ) {
      throw new BadRequestException(
        'Este quiz não está disponível para novas tentativas.',
      );
    }

    const account =
      await this.prisma.users.findUnique({
        where: {
          id: user.sub,
        },
        select: {
          id: true,
          status: true,
          person: {
            select: {
              id: true,
              status: true,
              congregation_id: true,
            },
          },
        },
      });

    if (
      !account ||
      account.status !== 'A' ||
      account.person.status !== 'A'
    ) {
      throw new ForbiddenException(
        'Usuário inválido ou inativo.',
      );
    }

    const congregationId =
      account.person.congregation_id;

    if (!congregationId) {
      throw new BadRequestException(
        'A pessoa precisa pertencer a uma congregação para responder o quiz.',
      );
    }

    const congregation =
      await this.prisma.congregations.findUnique({
        where: {
          id: congregationId,
        },
      });

    if (
      !congregation ||
      congregation.status !== 'A'
    ) {
      throw new BadRequestException(
        'A congregação da pessoa está inválida ou inativa.',
      );
    }

    const questions =
      quiz.quiz_questions;

    if (
      questions.length === 0
    ) {
      throw new BadRequestException(
        'O quiz não possui perguntas.',
      );
    }

    if (
      dto.answers.length !==
      questions.length
    ) {
      throw new BadRequestException(
        'Todas as perguntas do quiz devem ser respondidas.',
      );
    }

    const submittedQuestionIds =
      new Set(
        dto.answers.map(
          (answer) =>
            answer.questionId,
        ),
      );

    if (
      submittedQuestionIds.size !==
      dto.answers.length
    ) {
      throw new BadRequestException(
        'Uma pergunta não pode ser respondida mais de uma vez na mesma tentativa.',
      );
    }

    const questionMap =
      new Map(
        questions.map(
          (question) => [
            question.id,
            question,
          ],
        ),
      );

    const preparedAnswers =
      dto.answers.map(
        (answer) => {
          const question =
            questionMap.get(
              answer.questionId,
            );

          if (!question) {
            throw new BadRequestException(
              'Uma das perguntas enviadas não pertence a este quiz.',
            );
          }

          const selectedOption =
            question.quiz_options.find(
              (option) =>
                option.id ===
                answer.selectedOptionId,
            );

          if (!selectedOption) {
            throw new BadRequestException(
              'Uma das alternativas selecionadas não pertence à pergunta informada.',
            );
          }

          const isCorrect =
            selectedOption.is_correct;

          return {
            questionId:
              question.id,
            selectedOptionId:
              selectedOption.id,
            isCorrect,
            pointsAwarded:
              isCorrect
                ? question.points
                : 0,
          };
        },
      );

    const score =
      preparedAnswers.reduce(
        (
          total,
          answer,
        ) =>
          total +
          answer.pointsAwarded,
        0,
      );

    const correctAnswers =
      preparedAnswers.filter(
        (answer) =>
          answer.isCorrect,
      ).length;

    return this.prisma.$transaction(
      async (tx) => {
        const attemptsUsed =
          await tx.quiz_attempts.count({
            where: {
              quiz_id: quizId,
              user_id: user.sub,
              status: 'A',
            },
          });

        if (
          attemptsUsed >=
          quiz.max_attempts
        ) {
          throw new BadRequestException(
            'O limite de tentativas deste quiz foi atingido.',
          );
        }

        const attempt =
          await tx.quiz_attempts.create({
            data: {
              quiz_id: quizId,
              user_id:
                user.sub,
              congregation_id:
                congregationId,
              score,
              correct_answers:
                correctAnswers,
              total_questions:
                questions.length,
              status: 'A',
            },
          });

        await tx.quiz_answers.createMany({
          data:
            preparedAnswers.map(
              (answer) => ({
                attempt_id:
                  attempt.id,
                question_id:
                  answer.questionId,
                selected_option_id:
                  answer.selectedOptionId,
                is_correct:
                  answer.isCorrect,
                points_awarded:
                  answer.pointsAwarded,
                status: 'A',
              }),
            ),
        });

        return {
          id:
            attempt.id,
          quizId,
          attemptNumber:
            attemptsUsed + 1,
          score,
          correctAnswers,
          totalQuestions:
            questions.length,
          createdAt:
            attempt.created_at,
        };
      },
    );
  }

  async getMyAttempts(
    user: AccessTokenPayload,
    quizId: number,
  ) {
    const quiz =
      await this.quizzesService.getQuizOrThrow(
        quizId,
      );

    if (
      quiz.quiz_state === 'DRAFT'
    ) {
      await this.quizzesService.ensureCanManageQuiz(
        user,
        quiz.created_by_user_id,
      );
    }

    return this.prisma.quiz_attempts.findMany({
      where: {
        quiz_id: quizId,
        user_id: user.sub,
        status: 'A',
      },
      select: {
        id: true,
        score: true,
        correct_answers: true,
        total_questions: true,
        congregation_id: true,
        created_at: true,
      },
      orderBy: {
        created_at: 'desc',
      },
    });
  }

  async getRanking(
    user: AccessTokenPayload,
    quizId: number,
    congregationId?: number,
  ) {
    const quiz =
      await this.quizzesService.getQuizOrThrow(
        quizId,
      );

    if (
      quiz.quiz_state === 'DRAFT'
    ) {
      await this.quizzesService.ensureCanManageQuiz(
        user,
        quiz.created_by_user_id,
      );
    }

    const attempts =
      await this.prisma.quiz_attempts.findMany({
        where: {
          quiz_id: quizId,
          status: 'A',
          ...(
            congregationId !==
            undefined
              ? {
                  congregation_id:
                    congregationId,
                }
              : {}
          ),
        },
        select: {
          id: true,
          user_id: true,
          congregation_id: true,
          score: true,
          correct_answers: true,
          total_questions: true,
          created_at: true,
          users: {
            select: {
              id: true,
              username: true,
              person: {
                select: {
                  id: true,
                  full_name: true,
                  preferred_name: true,
                },
              },
            },
          },
        },
        orderBy: [
          {
            score: 'desc',
          },
          {
            correct_answers: 'desc',
          },
          {
            created_at: 'asc',
          },
          {
            id: 'asc',
          },
        ],
      });

    const bestByUser =
      new Map<
        number,
        (typeof attempts)[number]
      >();

    for (
      const attempt
      of attempts
    ) {
      if (
        !bestByUser.has(
          attempt.user_id,
        )
      ) {
        bestByUser.set(
          attempt.user_id,
          attempt,
        );
      }
    }

    return Array.from(
      bestByUser.values(),
    ).map(
      (
        attempt,
        index,
      ) => ({
        position:
          index + 1,
        attemptId:
          attempt.id,
        user:
          attempt.users,
        congregationId:
          attempt.congregation_id,
        score:
          attempt.score,
        correctAnswers:
          attempt.correct_answers,
        totalQuestions:
          attempt.total_questions,
        createdAt:
          attempt.created_at,
      }),
    );
  }
}