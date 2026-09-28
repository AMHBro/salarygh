import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Roles } from '../../common/decorators/roles.decorator';
import { FloorService } from './floor.service';

@ApiTags('Floor')
@ApiBearerAuth()
@Controller('floor')
export class FloorController {
  constructor(private readonly floor: FloorService) {}

  @Post('holds')
  hold(
    @Body()
    body: {
      variant_id?: string;
      warehouse_id?: string;
      quantity?: number;
      hold_key?: string;
    },
  ) {
    return this.floor.hold({
      variantId: body.variant_id ?? '',
      warehouseId: body.warehouse_id ?? '',
      quantity: Number(body.quantity ?? 0),
      holdKey: body.hold_key ?? '',
    });
  }

  @Delete('holds/:holdKey')
  releaseHold(@Param('holdKey') holdKey: string) {
    return this.floor.releaseHold(holdKey);
  }

  @Get('events')
  events(@Query('after') after?: string) {
    return this.floor.listEvents(Number(after ?? 0));
  }

  @Post('notices')
  notices(@Body() body: Record<string, unknown>) {
    return this.floor.publishNotice(body as never);
  }

  @Post('locks/release')
  @Roles('ADMIN', 'MANAGER')
  releaseLock(@Body() body: { variant_id?: string }) {
    return this.floor.releaseLock(body.variant_id ?? '');
  }
}
