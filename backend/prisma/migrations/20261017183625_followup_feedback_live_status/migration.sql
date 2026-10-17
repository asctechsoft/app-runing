-- AlterTable
ALTER TABLE "LiveShare" ADD COLUMN "lastStatus" TEXT;

-- CreateTable
CREATE TABLE "Feedback" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "ownerId" TEXT,
    "message" TEXT NOT NULL,
    "diagnostics" TEXT,
    "appVersion" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateIndex
CREATE INDEX "Feedback_ownerId_idx" ON "Feedback"("ownerId");
