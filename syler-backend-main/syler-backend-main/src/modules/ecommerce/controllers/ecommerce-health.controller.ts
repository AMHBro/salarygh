import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../../common/decorators/public.decorator';

@ApiTags('Ecommerce — M08')
@Public()
@Controller('ecommerce')
export class EcommerceHealthController {
    @Get('health')
    health() {
        return {
            success: true,
            data: {
                module: 'M12 Ecommerce',
                status: 'OK',
            },
        };
    }
}