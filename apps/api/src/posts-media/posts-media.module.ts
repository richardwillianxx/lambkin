import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ImageAuthorizationController } from './image-authorization.controller';
import { ImageAuthorizationService } from './image-authorization.service';
import { PostsController } from './posts.controller';
import { PostsService } from './posts.service';

@Module({
  imports: [
    AuthModule,
  ],
  controllers: [
    PostsController,
    ImageAuthorizationController,
  ],
  providers: [
    PostsService,
    ImageAuthorizationService,
  ],
})
export class PostsMediaModule {}