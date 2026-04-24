import 'reflect-metadata';
import { describe, expect, it } from 'vitest';
import {
  BasicConstraintsExtension,
  KeyUsageFlags,
  KeyUsagesExtension,
  X509Certificate,
  X509CertificateGenerator,
} from '@peculiar/x509';
import { verifyX5cChainAgainstRoot } from '~/lib/appStoreServerApi';

describe('verifyX5cChainAgainstRoot', () => {
  it('accepts a leaf certificate signed by the trusted root', async () => {
    const rootKeys = await generateEcKeys();
    const leafKeys = await generateEcKeys();
    const root = await createRoot('CN=Trusted Test Root', rootKeys);
    const leaf = await X509CertificateGenerator.create({
      subject: 'CN=Leaf',
      issuer: root.subject,
      publicKey: leafKeys.publicKey,
      signingKey: rootKeys.privateKey,
      notBefore: new Date(Date.now() - 60_000),
      notAfter: new Date(Date.now() + 86_400_000),
      extensions: [new BasicConstraintsExtension(false, undefined, true)],
    });

    const leafPem = await verifyX5cChainAgainstRoot([toBase64(leaf)], toPem(root));
    expect(new X509Certificate(leafPem).subject).toBe(leaf.subject);
  });

  it('rejects an attacker leaf when the trusted root is merely appended', async () => {
    const trustedRootKeys = await generateEcKeys();
    const attackerRootKeys = await generateEcKeys();
    const attackerLeafKeys = await generateEcKeys();
    const trustedRoot = await createRoot('CN=Trusted Test Root', trustedRootKeys);
    const attackerRoot = await createRoot('CN=Attacker Root', attackerRootKeys);
    const attackerLeaf = await X509CertificateGenerator.create({
      subject: 'CN=Attacker Leaf',
      issuer: attackerRoot.subject,
      publicKey: attackerLeafKeys.publicKey,
      signingKey: attackerRootKeys.privateKey,
      notBefore: new Date(Date.now() - 60_000),
      notAfter: new Date(Date.now() + 86_400_000),
      extensions: [new BasicConstraintsExtension(false, undefined, true)],
    });

    await expect(
      verifyX5cChainAgainstRoot([toBase64(attackerLeaf), toBase64(trustedRoot)], toPem(trustedRoot)),
    ).rejects.toMatchObject({ reason: 'chain_issuer_mismatch' });
  });
});

function generateEcKeys(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ]);
}

function createRoot(name: string, keys: CryptoKeyPair): Promise<X509Certificate> {
  return X509CertificateGenerator.createSelfSigned({
    name,
    keys,
    notBefore: new Date(Date.now() - 60_000),
    notAfter: new Date(Date.now() + 86_400_000),
    extensions: [
      new BasicConstraintsExtension(true, undefined, true),
      new KeyUsagesExtension(KeyUsageFlags.keyCertSign, true),
    ],
  });
}

function toBase64(cert: X509Certificate): string {
  return cert.toString('base64');
}

function toPem(cert: X509Certificate): string {
  const base64 = toBase64(cert);
  const lines = base64.match(/.{1,64}/g) ?? [];
  return ['-----BEGIN CERTIFICATE-----', ...lines, '-----END CERTIFICATE-----'].join('\n');
}
