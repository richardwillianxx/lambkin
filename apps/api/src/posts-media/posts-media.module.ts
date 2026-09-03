import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ImageAuthorizationController } from './image-authorization.controller';
import { ImageAuthorizationService } from './image-authorization.service';
import { MediaController } from './media.controller';
import { MediaService } from './media.service';
import { MediaStorageService } from './media-storage.service';
import { PostsController } from './posts.controller';
import { PostsService } from './posts.service';

@Module({
  imports: [AuthModule],
  controllers: [PostsController, ImageAuthorizationController, MediaController],
  providers: [
    PostsService,
    ImageAuthorizationService,
    MediaService,
    MediaStorageService,
  ],
})
export class PostsMediaModule {}
