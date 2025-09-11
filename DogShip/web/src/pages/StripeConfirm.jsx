import React, { useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { loadStripe } from '@stripe/stripe-js';
import { Elements, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';

const stripePromise = loadStripe(import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY);

function CheckoutInner() {
  const stripe = useStripe();
  const elements = useElements();
  const nav = useNavigate();

  async function onSubmit(e) {
    e.preventDefault();
    const { error } = await stripe.confirmPayment({
      elements,
      confirmParams: {},
      redirect: 'if_required'
    });
    if (error) alert(error.message);
    else { alert('Payment confirmed'); nav('/owner'); }
  }
  return (
    <form onSubmit={onSubmit} style={{ maxWidth: 480 }}>
      <PaymentElement />
      <button style={{ marginTop: 12 }}>Pay</button>
    </form>
  );
}

export default function StripeConfirm() {
  const { state } = useLocation();
  const [options, setOptions] = useState(null);
  useEffect(() => { if (state?.clientSecret) setOptions({ clientSecret: state.clientSecret }); }, [state]);
  if (!options) return <div>Missing client secret</div>;
  return (
    <Elements stripe={stripePromise} options={options}>
      <CheckoutInner />
    </Elements>
  );
}
