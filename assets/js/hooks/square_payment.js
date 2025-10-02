// Square Web Payments SDK Hook for Phoenix LiveView
export default {
  async mounted() {
    // Check if Square is loaded
    if (!window.Square) {
      console.error("Square Web Payments SDK not loaded");
      this.el.innerHTML = '<div class="text-red-500">Payment system unavailable. Please refresh the page.</div>';
      return;
    }

    try {
      // Initialize Square payments
      const appId = this.el.dataset.appId || 'sandbox-app-id';
      const locationId = this.el.dataset.locationId || 'sandbox-location-id';

      const payments = window.Square.payments(appId, locationId);

      // Create card payment method
      const card = await payments.card();

      // Find the container for the card
      const cardContainer = this.el.querySelector('#card-container');
      if (!cardContainer) {
        throw new Error("Card container not found");
      }

      // Attach to the card container
      await card.attach(cardContainer);

      // Store card instance for later use
      this.card = card;

      // Initialize Google Pay if available
      await this.initializeGooglePay(payments);

      // Hide loading message after everything is initialized
      const loadingMsg = this.el.querySelector('#loading-message');
      if (loadingMsg) {
        loadingMsg.style.display = 'none';
      }

      // Store button click handler so we can remove it later
      this.handleButtonClick = async (e) => {
        e.preventDefault();
        await this.tokenizeCard();
      };

      // Listen for the payment button click
      const paymentButton = document.getElementById('payment-button');
      if (paymentButton) {
        // Remove any existing listeners first
        const newButton = paymentButton.cloneNode(true);
        paymentButton.parentNode.replaceChild(newButton, paymentButton);

        // Add our click handler
        newButton.addEventListener('click', this.handleButtonClick);
      } else {
        console.error("Payment button not found!");
      }
    } catch (error) {
      console.error("Failed to initialize Square payments:", error);
      this.el.innerHTML = '<div class="text-red-500">Failed to load payment form. Please try again.</div>';
    }
  },

  async tokenizeCard() {
    if (!this.card) {
      console.error("Card not initialized");
      this.showError("Payment form not ready. Please refresh and try again.");
      return;
    }

    try {
      // Show loading state
      const button = document.getElementById('payment-button');
      const originalText = button.innerText;
      button.disabled = true;
      button.innerText = 'Processing...';

      // Tokenize the card
      const result = await this.card.tokenize();

      // Note: Square automatically clears the card form after tokenization for security
      // If there's an error, we'll need to let the user re-enter card details

      if (result.status === 'OK') {
        // Get plan information from data attributes
        const planId = this.el.dataset.planId;
        const planName = this.el.dataset.planName;
        const planPrice = this.el.dataset.planPrice;

        // Send token to LiveView with plan information
        this.pushEvent("process_subscription", {
          card_id: result.token,
          plan_id: planId,
          card_details: {
            last_4: result.details?.card?.last4,
            brand: result.details?.card?.brand,
            exp_month: result.details?.card?.expMonth,
            exp_year: result.details?.card?.expYear
          }
        });
      } else {
        // Show error
        console.error("Tokenization failed:", result.errors);
        this.showError(result.errors?.[0]?.message || "Payment failed. Please try again.");

        // Reset button
        button.disabled = false;
        button.innerText = originalText;
      }
    } catch (error) {
      console.error("Tokenization error:", error);
      this.showError("An error occurred. Please try again.");

      // Reset button
      const button = document.getElementById('payment-button');
      button.disabled = false;
      button.innerText = 'Subscribe Now';
    }
  },

  showError(message) {
    // You could also push this to LiveView to show in flash
    const errorDiv = document.createElement('div');
    errorDiv.className = 'text-red-500 text-sm mt-2';
    errorDiv.innerText = message;

    // Remove any existing error
    const existingError = this.el.parentNode.querySelector('.text-red-500');
    if (existingError) {
      existingError.remove();
    }

    this.el.parentNode.appendChild(errorDiv);

    // Remove error after 5 seconds
    setTimeout(() => {
      errorDiv.remove();
    }, 5000);
  },

  updated() {
    // Reset button state if it exists and is disabled
    const button = document.getElementById('payment-button');
    if (button && button.disabled) {
      button.disabled = false;

      // Reset button text based on plan type
      const planId = this.el.dataset.planId;
      if (planId && planId.includes('week_pass')) {
        button.innerText = 'Purchase Now';
      } else {
        button.innerText = 'Subscribe Now';
      }
    }

    // Hide loading message if card is initialized
    const loadingMsg = this.el.querySelector('#loading-message');
    const cardContainer = this.el.querySelector('#card-container');

    if (this.card && cardContainer && cardContainer.children.length > 0) {
      // Card exists and container has content - form is working
      if (loadingMsg) {
        loadingMsg.style.display = 'none';
      }
    } else if (this.card && cardContainer && cardContainer.children.length === 0) {
      // Card instance exists but container is empty - need to reinitialize
      // Destroy the old card instance
      try {
        this.card.destroy();
      } catch (e) {
        console.log("Error destroying card:", e);
      }
      this.card = null;

      // Show loading message
      if (loadingMsg) {
        loadingMsg.style.display = 'block';
      }

      // Re-initialize the payment form
      this.reinitializePaymentForm().catch(err => {
        console.error("Reinitialize failed in updated():", err);
      });
    }
  },

  async reinitializePaymentForm() {
    if (!window.Square) {
      console.error("Square SDK not available");
      return;
    }

    try {
      const appId = this.el.dataset.appId;
      const locationId = this.el.dataset.locationId;
      const payments = window.Square.payments(appId, locationId);

      // Create new card instance
      const card = await payments.card();
      const cardContainer = this.el.querySelector('#card-container');

      if (cardContainer) {
        await card.attach(cardContainer);
        this.card = card;

        const loadingMsg = this.el.querySelector('#loading-message');
        if (loadingMsg) {
          loadingMsg.style.display = 'none';
        }
      } else {
        console.error("Card container not found during reinitialize");
      }
    } catch (error) {
      console.error("Failed to reinitialize payment form:", error);

      // Show error to user
      const loadingMsg = this.el.querySelector('#loading-message');
      if (loadingMsg) {
        loadingMsg.textContent = 'Failed to load payment form. Please refresh and try again.';
        loadingMsg.style.color = 'red';
      }
    }
  },

  destroyed() {
    // Remove event listener
    const paymentButton = document.getElementById('payment-button');
    if (paymentButton && this.handleButtonClick) {
      paymentButton.removeEventListener('click', this.handleButtonClick);
    }

    // Clean up payment instances
    if (this.card) {
      this.card.destroy();
      this.card = null;
    }
    if (this.googlePay) {
      this.googlePay.destroy();
      this.googlePay = null;
    }
  },

  async initializeGooglePay(payments) {
    try {
      const paymentRequest = this.buildPaymentRequest();
      const googlePay = await payments.googlePay(paymentRequest);

      // Check if Google Pay is available on this device/browser
      if (googlePay !== undefined) {
        const googlePayContainer = this.el.querySelector('#google-pay-button-container');
        if (googlePayContainer) {
          await googlePay.attach('#google-pay-button-container');
          this.googlePay = googlePay;

          // Add click handler for Google Pay
          googlePayContainer.addEventListener('click', async () => {
            await this.tokenizeGooglePay();
          });

          // Show the divider since we have Google Pay
          const divider = document.getElementById('payment-divider');
          if (divider) {
            divider.classList.remove('hidden');
          }
        }
      }
    } catch (error) {
      // Hide Google Pay button if not available
      const googlePayContainer = this.el.querySelector('#google-pay-button-container');
      if (googlePayContainer) {
        googlePayContainer.style.display = 'none';
      }
    }
  },

  buildPaymentRequest() {
    // Get plan details from data attributes or use defaults
    const planName = this.el.dataset.planName || 'Premium Subscription';
    const planPrice = this.el.dataset.planPrice || '999'; // in cents

    return {
      countryCode: 'US',
      currencyCode: 'USD',
      total: {
        amount: planPrice,
        label: planName
      }
    };
  },

  async tokenizeGooglePay() {
    if (!this.googlePay) {
      console.error("Google Pay not initialized");
      return;
    }

    try {
      const result = await this.googlePay.tokenize();
      if (result.status === 'OK') {
        this.pushEvent("process_payment", { nonce: result.token });
      } else {
        this.showError("Google Pay was cancelled");
      }
    } catch (error) {
      console.error("Google Pay tokenization error:", error);
      this.showError("Google Pay failed. Please try another payment method.");
    }
  }
}