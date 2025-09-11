import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, ActivityIndicator } from 'react-native';
import { authFetch } from '../../utils/api';

export default function TransporterProfileScreen({ route }) {
  const { userId } = route.params;
  const [profile, setProfile] = useState(null);
  const [reviews, setReviews] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const p = await authFetch(`/users/${userId}/profile`);
        const r = await authFetch(`/users/${userId}/reviews?limit=20`);
        setProfile(p); setReviews(r);
      } finally { setLoading(false); }
    })();
  }, [userId]);

  if (loading) return <View style={{ flex:1, justifyContent:'center', alignItems:'center' }}><ActivityIndicator /></View>;
  if (!profile) return <View style={{ padding:16 }}><Text>Profile not found.</Text></View>;

  return (
    <View style={{ flex:1, padding:16 }}>
      <Text style={{ fontSize:20, fontWeight:'700' }}>{profile.email}</Text>
      <Text>Role: {profile.role}</Text>
      <Text>⭐ {Number(profile.avg_rating).toFixed(1)} ({profile.review_count} reviews)</Text>
      <Text>Avg response: {Number(profile.avg_response_minutes).toFixed(1)} min</Text>
      <Text>Completed trips: {profile.completed_trips}</Text>

      <View style={{ height:16 }} />
      <Text style={{ fontWeight:'700', fontSize:16 }}>Recent Reviews</Text>
      <FlatList
        data={reviews}
        keyExtractor={(x) => String(x.id)}
        renderItem={({ item }) => (
          <View style={{ borderWidth:1, borderRadius:8, padding:12, marginTop:8 }}>
            <Text>⭐ {item.rating} — {new Date(item.created_at).toLocaleDateString()}</Text>
            <Text>From: {item.reviewer_email}</Text>
            <Text>{item.comment || '—'}</Text>
          </View>
        )}
        ListEmptyComponent={<Text>No reviews yet.</Text>}
      />
    </View>
  );
}
