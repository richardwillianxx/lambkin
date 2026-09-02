import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { AccessTokenPayload } from '../auth/auth.types';
import { CreatePostDto, UpdatePostDto } from './dto/post.dto';
import { ReactToPostDto } from './dto/reaction.dto';

@Injectable()
export class PostsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AccessTokenPayload, dto: CreatePostDto) {
    if (dto.congregationId !== undefined) {
      await this.ensureCanPostForCongregation(user, dto.congregationId);
    }

    return this.prisma.posts.create({
      data: {
        author_user_id: user.sub,
        congregation_id: dto.congregationId ?? null,
        caption: dto.caption,
        status: 'A',
      },
    });
  }

  async findAll() {
    return this.prisma.posts.findMany({
      where: {
        status: 'A',
      },
      include: {
        users: {
          select: {
            id: true,
            username: true,
            person: {
              select: {
                id: true,
                full_name: true,
                preferred_name: true,
                role: true,
              },
            },
          },
        },
        post_reactions: {
          where: {
            status: 'A',
          },
          select: {
            id: true,
            user_id: true,
            reaction_type: true,
            created_at: true,
          },
        },
        post_media: {
          where: {
            status: 'A',
          },
          orderBy: {
            position: 'asc',
          },
          select: {
            id: true,
            position: true,
            media: {
              select: {
                id: true,
                original_filename: true,
                mime_type: true,
                size_bytes: true,
                status: true,
              },
            },
          },
        },
      },
      orderBy: {
        created_at: 'desc',
      },
    });
  }

  async findOne(id: number) {
    const post = await this.prisma.posts.findUnique({
      where: {
        id,
      },
      include: {
        users: {
          select: {
            id: true,
            username: true,
            person: {
              select: {
                id: true,
                full_name: true,
                preferred_name: true,
                role: true,
              },
            },
          },
        },
        post_reactions: {
          where: {
            status: 'A',
          },
          select: {
            id: true,
            user_id: true,
            reaction_type: true,
            created_at: true,
          },
        },
        post_media: {
          where: {
            status: 'A',
          },
          orderBy: {
            position: 'asc',
          },
          select: {
            id: true,
            position: true,
            media: {
              select: {
                id: true,
                original_filename: true,
                mime_type: true,
                size_bytes: true,
                status: true,
              },
            },
          },
        },
      },
    });

    if (!post || post.status !== 'A') {
      throw new NotFoundException('Publicação não encontrada.');
    }

    return post;
  }

  async update(user: AccessTokenPayload, postId: number, dto: UpdatePostDto) {
    const post = await this.ensurePostExists(postId);

    this.ensureCanManagePost(user, post.author_user_id);

    return this.prisma.posts.update({
      where: {
        id: postId,
      },
      data: {
        caption: dto.caption,
      },
    });
  }

  async remove(user: AccessTokenPayload, postId: number) {
    const post = await this.ensurePostExists(postId);

    this.ensureCanManagePost(user, post.author_user_id);

    await this.prisma.posts.update({
      where: {
        id: postId,
      },
      data: {
        status: 'I',
      },
    });

    return {
      message: 'Publicação removida.',
    };
  }

  async react(user: AccessTokenPayload, postId: number, dto: ReactToPostDto) {
    await this.ensurePostExists(postId);

    const existing = await this.prisma.post_reactions.findUnique({
      where: {
        post_id_user_id: {
          post_id: postId,
          user_id: user.sub,
        },
      },
    });

    if (existing) {
      return this.prisma.post_reactions.update({
        where: {
          id: existing.id,
        },
        data: {
          reaction_type: dto.reactionType,
          status: 'A',
        },
      });
    }

    return this.prisma.post_reactions.create({
      data: {
        post_id: postId,
        user_id: user.sub,
        reaction_type: dto.reactionType,
        status: 'A',
      },
    });
  }

  async removeReaction(user: AccessTokenPayload, postId: number) {
    await this.ensurePostExists(postId);

    const reaction = await this.prisma.post_reactions.findUnique({
      where: {
        post_id_user_id: {
          post_id: postId,
          user_id: user.sub,
        },
      },
    });

    if (!reaction || reaction.status !== 'A') {
      throw new NotFoundException('Reação não encontrada.');
    }

    await this.prisma.post_reactions.update({
      where: {
        id: reaction.id,
      },
      data: {
        status: 'I',
      },
    });

    return {
      message: 'Reação removida.',
    };
  }

  private async ensureCanPostForCongregation(
    user: AccessTokenPayload,
    congregationId: number,
  ) {
    const congregation = await this.prisma.congregations.findUnique({
      where: {
        id: congregationId,
      },
    });

    if (!congregation || congregation.status !== 'A') {
      throw new BadRequestException('Congregação inválida ou inativa.');
    }

    if (user.isSystemAdmin) {
      return;
    }

    const account = await this.prisma.users.findUnique({
      where: {
        id: user.sub,
      },
      include: {
        person: true,
      },
    });

    if (!account || account.person.status !== 'A') {
      throw new ForbiddenException(
        'Usuário sem permissão para publicar pela congregação.',
      );
    }

    const allowedRoles = ['MINISTRY', 'ASSISTANT'];

    if (!allowedRoles.includes(account.person.role)) {
      throw new ForbiddenException(
        'Usuário sem permissão para publicar pela congregação.',
      );
    }

    if (account.person.congregation_id !== congregationId) {
      throw new ForbiddenException('Usuário não pertence a esta congregação.');
    }
  }

  private ensureCanManagePost(user: AccessTokenPayload, authorUserId: number) {
    if (user.sub !== authorUserId && !user.isSystemAdmin) {
      throw new ForbiddenException(
        'Usuário sem permissão para alterar esta publicação.',
      );
    }
  }

  private async ensurePostExists(postId: number) {
    const post = await this.prisma.posts.findUnique({
      where: {
        id: postId,
      },
    });

    if (!post || post.status !== 'A') {
      throw new NotFoundException('Publicação não encontrada.');
    }

    return post;
  }
}
