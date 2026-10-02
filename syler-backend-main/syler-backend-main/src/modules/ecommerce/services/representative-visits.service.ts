import {
    BadRequestException,
    ConflictException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from 'src/prisma/prisma.service';

export class VisitBody {
    customer_id?: string;
    visit_id?: string;
    latitude?: number;
    longitude?: number;
    notes?: string;
    postponed_until?: string;
}

@Injectable()
export class RepresentativeVisitsService {
    constructor(private readonly prisma: PrismaService) {}

    async start(userId: string, body: VisitBody) {
        const representative = await this.requireRepresentative(userId);
        const customerId = body.customer_id?.trim();
        if (!customerId) {
            throw new BadRequestException({
                code: 'CUSTOMER_REQUIRED',
                message: 'الزبون مطلوب لبدء الزيارة',
            });
        }
        const visit = await this.prisma.representative_visits.create({
            data: {
                representative_id: representative.id,
                customer_id: customerId,
                status: 'in_progress',
                latitude: this.coordinate(body.latitude),
                longitude: this.coordinate(body.longitude),
                geofence_radius_m: 150,
                notes: body.notes?.trim() || null,
            },
        });
        return this.present(visit);
    }

    async end(userId: string, body: VisitBody) {
        const visit = await this.requireOpenVisit(userId, body.visit_id);
        const updated = await this.prisma.representative_visits.update({
            where: { id: visit.id },
            data: {
                status: 'completed',
                ended_at: new Date(),
                notes: body.notes?.trim() || visit.notes,
                updated_at: new Date(),
            },
        });
        return this.present(updated);
    }

    async postpone(userId: string, body: VisitBody) {
        const visit = await this.requireOpenVisit(userId, body.visit_id);
        const postponedUntil = body.postponed_until
            ? new Date(body.postponed_until)
            : null;
        if (postponedUntil && Number.isNaN(postponedUntil.getTime())) {
            throw new BadRequestException({
                code: 'POSTPONE_DATE_INVALID',
                message: 'تاريخ التأجيل غير صالح',
            });
        }
        const updated = await this.prisma.representative_visits.update({
            where: { id: visit.id },
            data: {
                status: 'postponed',
                ended_at: new Date(),
                postponed_until: postponedUntil,
                notes: body.notes?.trim() || visit.notes,
                updated_at: new Date(),
            },
        });
        return this.present(updated);
    }

    private async requireRepresentative(userId: string) {
        const representative = await this.prisma.representatives.findUnique({
            where: { user_id: userId },
            select: { id: true },
        });
        if (!representative) {
            throw new NotFoundException({
                code: 'REPRESENTATIVE_NOT_FOUND',
                message: 'المستخدم الحالي غير مرتبط بمندوب',
            });
        }
        return representative;
    }

    private async requireOpenVisit(userId: string, visitId?: string) {
        const representative = await this.requireRepresentative(userId);
        const id = visitId?.trim();
        if (!id) {
            throw new BadRequestException({
                code: 'VISIT_REQUIRED',
                message: 'معرّف الزيارة مطلوب',
            });
        }
        const visit = await this.prisma.representative_visits.findFirst({
            where: { id, representative_id: representative.id },
        });
        if (!visit) {
            throw new NotFoundException({
                code: 'VISIT_NOT_FOUND',
                message: 'الزيارة غير موجودة',
            });
        }
        if (visit.status !== 'in_progress') {
            throw new ConflictException({
                code: 'VISIT_CLOSED',
                message: 'الزيارة مغلقة',
            });
        }
        return visit;
    }

    private coordinate(value?: number): Prisma.Decimal | null {
        if (value == null || Number.isNaN(value)) return null;
        return new Prisma.Decimal(value);
    }

    private present(visit: {
        id: string;
        status: string;
        started_at: Date;
        ended_at: Date | null;
        postponed_until: Date | null;
        latitude: Prisma.Decimal | null;
        longitude: Prisma.Decimal | null;
        geofence_radius_m: number;
        customer_id: string | null;
    }) {
        return {
            id: visit.id,
            customer_id: visit.customer_id,
            status: visit.status,
            started_at: visit.started_at,
            ended_at: visit.ended_at,
            postponed_until: visit.postponed_until,
            geofence: {
                latitude: visit.latitude == null ? null : Number(visit.latitude.toString()),
                longitude: visit.longitude == null ? null : Number(visit.longitude.toString()),
                radius_meters: visit.geofence_radius_m,
            },
        };
    }
}
