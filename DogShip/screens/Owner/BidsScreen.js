import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, RefreshControl, Alert, Button } from 'react-native';
import { authFetch } from '../../utils/api';

const currency = (cents) => `$${(cents/100).toFixed(2)}`;

export default function BidsScreen({ route, navigation }) {
  const { tripId, feePercent = 15 } = route.params;
  const [bids, setBids] = useState([]);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      const data = await authFetch(`/bids/${tripId}`);
      setBids(data);
    } catch (e) {
      Alert.alert('Error', e.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [tripId]);

  const renderItem = ({ item }) => {
    const platformFee = Math.round(item.amount_cents * (feePercent/100));
    const transporterEarnings = item.amount_cents - platformFee;
    return (
      <TouchableOpacity
        style={{ padding: 12, borderWidth: 1, borderRadius: 8, marginBottom: 10 }}
        onPress={() => navigation.navigate('BidDetail', { bid: item, feePercent })}
      >
        <Text style={{ fontWeight: '700' }}>{currency(item.amount_cents)} • ETA {item.eta_hours || '?'}h</Text>
        <Text>{item.note || '—'}</Text>
        <Text onPress={() => navigation.navigate('TransporterProfile', { userId: item.transporter_id })}
          style={{ textDecorationLine: 'underline' }}>Transporter: {item.transporter_email || item.transporter_id}</Text>
        <Text>⭐ {Number(item.avg_rating||0).toFixed(1)} ({item.review_count}) • Response {Number(item.response_time_minutes||0).toFixed(1)} min</Text>
        <Text>Platform fee {feePercent}%: {currency(platformFee)} • Driver gets {currency(transporterEarnings)}</Text>
        <Text>Status: {item.status}</Text>
        <View style={{ height:8 }} />
        <Button title="Message transporter" onPress={() => navigation.navigate('Chat', { bidId: item.id })} />
      </TouchableOpacity>
    );
  };

  return (
    <View style={{ flex: 1, padding: 12 }}>
      <FlatList
        data={bids}
        keyExtractor={(b) => String(b.id)}
        renderItem={renderItem}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        ListEmptyComponent={!loading && (<Text>No bids yet. Pull to refresh.</Text>)}
      />
    </View>
  );
}
