import { Injectable } from '@nestjs/common';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { randomUUID } from 'node:crypto';

@Injectable()
export class MediaStorageService {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor() {
    const region = process.env.AWS_REGION;
    const bucket = process.env.AWS_S3_BUCKET;

    if (!region) {
      throw new Error('AWS_REGION não configurada.');
    }

    if (!bucket) {
      throw new Error('AWS_S3_BUCKET não configurado.');
    }

    this.bucket = bucket;

    this.client = new S3Client({
      region,
    });
  }

  generateStorageKey(userId: number, mimeType: string) {
    const now = new Date();

    const year = now.getUTCFullYear();

    const month = String(now.getUTCMonth() + 1).padStart(2, '0');

    const extension = this.getExtension(mimeType);

    return ['media', userId, year, month, `${randomUUID()}.${extension}`].join(
      '/',
    );
  }

  async createUploadUrl(storageKey: string, mimeType: string) {
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: storageKey,
      ContentType: mimeType,
    });

    return getSignedUrl(this.client, command, {
      expiresIn: 300,
    });
  }

  async createAccessUrl(storageKey: string) {
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: storageKey,
    });

    return getSignedUrl(this.client, command, {
      expiresIn: 300,
    });
  }

  async getObjectMetadata(storageKey: string) {
    return this.client.send(
      new HeadObjectCommand({
        Bucket: this.bucket,
        Key: storageKey,
      }),
    );
  }

  async deleteObject(storageKey: string) {
    await this.client.send(
      new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: storageKey,
      }),
    );
  }

  private getExtension(mimeType: string) {
    const extensions: Record<string, string> = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'video/mp4': 'mp4',
    };

    const extension = extensions[mimeType];

    if (!extension) {
      throw new Error('MIME type sem extensão configurada.');
    }

    return extension;
  }
}
