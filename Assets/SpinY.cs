using UnityEngine;

public class SpinY : MonoBehaviour
{
    public float speed = 45f;
    void Update() => transform.Rotate(0f, speed * Time.deltaTime, 0f, Space.World);
}
