import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { AccessTokenPayload } from '../auth/auth.types';
import { PrismaService } from '../prisma/prisma.service';
import {
  ConfirmMediaUploadDto,
  CreateMediaUploadUrlDto,
} from './dto/media.dto';
import { MediaStorageService } from './media-storage.service';

@Injectable()
export class MediaService {
  private readonly allowedTypes = new Set([
    'image/jpeg',
    'image/png',
    'image/webp',
    'video/mp4',
  ]);

  private readonly imageLimit = 10 * 1024 * 1024;

  private readonly videoLimit = 100 * 1024 * 1024;

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: MediaStorageService,
  ) {}

  async createUploadUrl(
    user: AccessTokenPayload,
    dto: CreateMediaUploadUrlDto,
  ) {
    this.validateMedia(dto.mimeType, dto.sizeBytes);

    const storageKey = this.storage.generateStorageKey(user.sub, dto.mimeType);

    const uploadUrl = await this.storage.createUploadUrl(
      storageKey,
      dto.mimeType,
    );

    return {
      storageKey,
      uploadUrl,
      expiresIn: 300,
      requiredHeaders: {
        'Content-Type': dto.mimeType,
      },
    };
  }

  async confirmUpload(user: AccessTokenPayload, dto: ConfirmMediaUploadDto) {
    this.validateMedia(dto.mimeType, dto.sizeBytes);

    this.ensureStorageKeyBelongsToUser(user.sub, dto.storageKey);

    const existing = await this.prisma.media.findUnique({
      where: {
        storage_key: dto.storageKey,
      },
    });

    if (existing) {
      if (existing.uploaded_by_user_id !== user.sub) {
        throw new ForbiddenException('Mídia pertence a outro usuário.');
      }

      return existing;
    }

    let objectMetadata;

    try {
      objectMetadata = await this.storage.getObjectMetadata(dto.storageKey);
    } catch {
      throw new BadRequestException('Arquivo não encontrado no armazenamento.');
    }

    if (objectMetadata.ContentLength !== dto.sizeBytes) {
      throw new BadRequestException(
        'Tamanho do arquivo enviado não corresponde ao informado.',
      );
    }

    const storedMimeType = objectMetadata.ContentType?.split(';')[0]
      .trim()
      .toLowerCase();

    if (storedMimeType !== dto.mimeType.toLowerCase()) {
      throw new BadRequestException(
        'Tipo do arquivo enviado não corresponde ao informado.',
      );
    }

    return this.prisma.media.create({
      data: {
        uploaded_by_user_id: user.sub,
        storage_key: dto.storageKey,
        original_filename: dto.originalFilename,
        mime_type: dto.mimeType,
        size_bytes: dto.sizeBytes,
        status: 'A',
      },
    });
  }

  async getAccessUrl(user: AccessTokenPayload, mediaId: number) {
    const media = await this.prisma.media.findFirst({
      where: {
        id: mediaId,
        status: 'A',
      },
      include: {
        post_media: {
          where: {
            status: 'A',
            posts: {
              status: 'A',
            },
          },
          select: {
            id: true,
          },
        },
      },
    });

    if (!media) {
      throw new NotFoundException('Mídia não encontrada.');
    }

    const isUploader = media.uploaded_by_user_id === user.sub;

    const isPublished = media.post_media.length > 0;

    if (!user.isSystemAdmin && !isUploader && !isPublished) {
      throw new ForbiddenException(
        'Usuário sem permissão para acessar esta mídia.',
      );
    }

    const url = await this.storage.createAccessUrl(media.storage_key);

    return {
      url,
      expiresIn: 300,
    };
  }

  async remove(user: AccessTokenPayload, mediaId: number) {
    const media = await this.prisma.media.findFirst({
      where: {
        id: mediaId,
        status: 'A',
      },
    });

    if (!media) {
      throw new NotFoundException('Mídia não encontrada.');
    }

    if (media.uploaded_by_user_id !== user.sub && !user.isSystemAdmin) {
      throw new ForbiddenException(
        'Usuário sem permissão para remover esta mídia.',
      );
    }

    await this.storage.deleteObject(media.storage_key);

    await this.prisma.$transaction([
      this.prisma.post_media.updateMany({
        where: {
          media_id: mediaId,
          status: 'A',
        },
        data: {
          status: 'I',
        },
      }),

      this.prisma.media.update({
        where: {
          id: mediaId,
        },
        data: {
          status: 'I',
        },
      }),
    ]);

    return {
      message: 'Mídia removida.',
    };
  }

  private validateMedia(mimeType: string, sizeBytes: number) {
    const normalizedMimeType = mimeType.toLowerCase();

    if (!this.allowedTypes.has(normalizedMimeType)) {
      throw new BadRequestException('Tipo de mídia não permitido.');
    }

    const isImage = normalizedMimeType.startsWith('image/');

    const maxSize = isImage ? this.imageLimit : this.videoLimit;

    if (sizeBytes > maxSize) {
      throw new BadRequestException(
        isImage
          ? 'Imagem excede o limite de 10 MB.'
          : 'Vídeo excede o limite de 100 MB.',
      );
    }
  }

  private ensureStorageKeyBelongsToUser(userId: number, storageKey: string) {
    const expectedPrefix = `media/${userId}/`;

    if (!storageKey.startsWith(expectedPrefix)) {
      throw new ForbiddenException('Storage key inválida para este usuário.');
    }
  }
}
