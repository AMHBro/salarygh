const PRIVATE_HOST =
    /^(localhost|127\.0\.0\.1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})$/;

export function allowedOriginsFromEnv(raw: string | undefined): string[] {
    if (!raw) {
        return [];
    }

    return raw
        .split(',')
        .map((value) => value.trim())
        .filter((value) => value.length > 0);
}

export function isAllowedOrigin(origin: string, extraOrigins: string[] = []): boolean {
    if (extraOrigins.includes(origin)) {
        return true;
    }

    let url: URL;
    try {
        url = new URL(origin);
    } catch {
        return false;
    }

    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
        return false;
    }

    return PRIVATE_HOST.test(url.hostname);
}
