import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import type { AccessTokenPayload } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreatePostDto, UpdatePostDto } from './dto/post.dto';
import { ReactToPostDto } from './dto/reaction.dto';
import { PostsService } from './posts.service';

@Controller('posts')
@UseGuards(JwtAuthGuard)
export class PostsController {
  constructor(private readonly postsService: PostsService) {}

  @Post()
  create(@CurrentUser() user: AccessTokenPayload, @Body() dto: CreatePostDto) {
    return this.postsService.create(user, dto);
  }

  @Get()
  findAll() {
    return this.postsService.findAll();
  }

  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.postsService.findOne(id);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdatePostDto,
  ) {
    return this.postsService.update(user, id, dto);
  }

  @Delete(':id')
  remove(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.postsService.remove(user, id);
  }

  @Post(':id/reaction')
  react(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ReactToPostDto,
  ) {
    return this.postsService.react(user, id, dto);
  }

  @Delete(':id/reaction')
  removeReaction(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.postsService.removeReaction(user, id);
  }
}
