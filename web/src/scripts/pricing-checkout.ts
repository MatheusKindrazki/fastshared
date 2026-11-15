import {
  ApiError,
  apiJson,
  clearToken,
  priceIdFor,
  readToken,
  userIdFromMe,
  type BillingConfig,
  type MeResponse,
} from './session';

type PaddleGlobal = {
  Environment: { set: (value: 'sandbox' | 'production') => void };
  Initialize: (options: { token: string }) => void;
  Checkout: {
    open: (options: {
      items: Array<{ priceId: string; quantity: number }>;
      customData: { userId: string };
    }) => void;
  };
};

declare global {
  interface Window {
    Paddle?: PaddleGlobal;
  }
}

const PADDLE_SRC = 'https://cdn.paddle.com/paddle/v2/paddle.js';
let paddlePromise: Promise<PaddleGlobal> | null = null;
let initializedFor: string | null = null;

function loadPaddle(): Promise<PaddleGlobal> {
  if (window.Paddle) return Promise.resolve(window.Paddle);
  if (paddlePromise) return paddlePromise;
  paddlePromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = PADDLE_SRC;
    script.async = true;
    script.onload = () => {
      if (window.Paddle) resolve(window.Paddle);
      else reject(new Error('Checkout could not be loaded.'));
    };
    script.onerror = () => reject(new Error('Checkout could not be loaded.'));
    document.head.append(script);
  });
  return paddlePromise;
}

async function openCheckout(cycle: 'monthly' | 'annual', status: HTMLElement): Promise<void> {
  const token = readToken();
  if (!token) {
    status.textContent = 'Sign in before checkout.';
    return;
  }
  status.textContent = 'Opening checkout.';
  const me = await apiJson<MeResponse>('/v1/me', { token });
  const userId = userIdFromMe(me);
  if (!userId) {
    status.textContent = 'Checkout needs a user id from your account. Sign in again once billing is connected.';
    return;
  }
  const config = await apiJson<BillingConfig>('/v1/billing/config');
  const priceId = priceIdFor(config.priceIds, cycle);
  if (!config.clientToken || !priceId) {
    status.textContent = 'Checkout is not configured yet.';
    return;
  }
  const paddle = await loadPaddle();
  const marker = `${config.environment ?? 'production'}:${config.clientToken}`;
  if (initializedFor !== marker) {
    if (config.environment === 'sandbox') paddle.Environment.set('sandbox');
    paddle.Initialize({ token: config.clientToken });
    initializedFor = marker;
  }
  paddle.Checkout.open({
    items: [{ priceId, quantity: 1 }],
    customData: { userId },
  });
  status.textContent = '';
}

export function mountPricing(root: HTMLElement): void {
  const status = root.querySelector<HTMLElement>('[data-checkout-status]');
  if (!status) return;
  root.querySelectorAll<HTMLButtonElement>('[data-checkout]').forEach((button) => {
    button.addEventListener('click', () => {
      const cycle = button.dataset.checkout === 'annual' ? 'annual' : 'monthly';
      button.disabled = true;
      void openCheckout(cycle, status)
        .catch((error: unknown) => {
          if (error instanceof ApiError && error.status === 401) clearToken();
          status.textContent = error instanceof Error ? error.message : 'Checkout could not be opened.';
        })
        .finally(() => {
          button.disabled = false;
        });
    });
  });
}

const root = document.querySelector<HTMLElement>('[data-pricing-root]');
if (root) mountPricing(root);
