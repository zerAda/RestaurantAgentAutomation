--
-- PostgreSQL database cluster dump
--

\restrict dlY7R8wwU7a6fNHPSh3DlTDKAtc4hZFeExiIEESV1lBcKh51HLmdcPxynjwqzxu

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE n8n;
ALTER ROLE n8n WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:H0eWFbJP1baBiQdq3TMEgg==$LgfOnHrrAUb2vuQnMdjVF+8sWJ0hWJENWAeY56F4Vyk=:53b4d20k3F1SnE3c1j54ubbLKtd8gN/wL1Hcek7rty0=';
CREATE ROLE strapi;
ALTER ROLE strapi WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:Dcr+vDVwnrtsB0Lyrehj7Q==$+EmSHiLkRGyHUTu/BPvFWREloJf3rbzfBlCBYp+pLPg=:kgsJFyGzSxpyy+O32fKs+b7LdzAK9TNXT5zgUUbILZ4=';
COMMENT ON ROLE strapi IS 'Dedicated Strapi CMS user with limited privileges (strapi DB only)';

--
-- User Configurations
--








\unrestrict dlY7R8wwU7a6fNHPSh3DlTDKAtc4hZFeExiIEESV1lBcKh51HLmdcPxynjwqzxu

--
-- PostgreSQL database cluster dump complete
--

