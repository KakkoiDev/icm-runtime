CREATE TABLE "Note" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL DEFAULT tenant_id(),
    "companyId" TEXT NOT NULL DEFAULT company_id(),
    "body" TEXT NOT NULL,
    CONSTRAINT "Note_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "Tag" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL DEFAULT tenant_id(),
    CONSTRAINT "Tag_pkey" PRIMARY KEY ("id")
);

SELECT enable_company_rls('Note');
SELECT enable_tenant_rls('Tag');
ALTER TABLE "Note" ENABLE ROW LEVEL SECURITY;
