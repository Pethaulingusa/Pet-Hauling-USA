import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from './firebase';
import { StripeProvider } from '@stripe/stripe-react-native';

// Screens (owner)
import LoginScreen from './screens/LoginScreen';
import OwnerHome from './screens/Owner/HomeScreen';
import OwnerPostTrip from './screens/Owner/PostTripScreen';
import OwnerTripDetail from './screens/Owner/TripDetailScreen';
import BidsScreen from './screens/Owner/BidsScreen';
import BidDetailScreen from './screens/Owner/BidDetailScreen';
import TransporterProfileScreen from './screens/Owner/TransporterProfileScreen';
import LeaveReviewScreen from './screens/Owner/LeaveReviewScreen';

// Screens (transporter)
import TransporterHome from './screens/Transporter/HomeScreen';
import TripApply from './screens/Transporter/TripApplyScreen';
import PlaceBidScreen from './screens/Transporter/PlaceBidScreen';
import MyBidsScreen from './screens/Transporter/MyBidsScreen';
import AwardedTripsScreen from './screens/Transporter/AwardedTripsScreen';
import MarketScreen from './screens/Transporter/MarketScreen';

// Chat
import ChatScreen from './screens/Chat/ChatScreen';

const Stack = createNativeStackNavigator();

export default function App() {
  const [user, setUser] = useState(null);
  const [role, setRole] = useState(null);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => {
      setUser(u);
      setRole(u?.displayName || 'owner');
    });
    return unsub;
  }, []);

  const publishableKey = process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY;

  return (
    <StripeProvider publishableKey={publishableKey}>
      <NavigationContainer>
        <Stack.Navigator>
          {!user ? (
            <Stack.Screen name="Login" component={LoginScreen} />
          ) : role === 'transporter' ? (
            <>
              <Stack.Screen name="TransporterHome" component={TransporterHome} />
              <Stack.Screen name="Market" component={MarketScreen} />
              <Stack.Screen name="TripApply" component={TripApply} />
              <Stack.Screen name="PlaceBid" component={PlaceBidScreen} />
              <Stack.Screen name="MyBids" component={MyBidsScreen} />
              <Stack.Screen name="AwardedTrips" component={AwardedTripsScreen} />
              <Stack.Screen name="Chat" component={ChatScreen} />
            </>
          ) : (
            <>
              <Stack.Screen name="OwnerHome" component={OwnerHome} />
              <Stack.Screen name="PostTrip" component={OwnerPostTrip} />
              <Stack.Screen name="TripDetail" component={OwnerTripDetail} />
              <Stack.Screen name="Bids" component={BidsScreen} />
              <Stack.Screen name="BidDetail" component={BidDetailScreen} />
              <Stack.Screen name="TransporterProfile" component={TransporterProfileScreen} />
              <Stack.Screen name="LeaveReview" component={LeaveReviewScreen} />
              <Stack.Screen name="Chat" component={ChatScreen} />
            </>
          )}
        </Stack.Navigator>
      </NavigationContainer>
    </StripeProvider>
  );
}
