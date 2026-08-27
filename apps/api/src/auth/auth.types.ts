export enum VerificationChannel {
  EMAIL = 'EMAIL',
  WHATSAPP = 'WHATSAPP',
}

export interface AccessTokenPayload {
  sub: number;
  personId: number;
  sessionId: number;
  username: string;
  isSystemAdmin: boolean;
}